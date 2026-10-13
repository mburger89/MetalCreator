import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// A selected Field Scatter shows its points as axis triads (fields spec §6), sized by the nearest neighbours.
@MainActor
struct ScatterPreviewTests {
    func plane(_ x: Double, _ y: Double = 0) -> Plane { Plane(origin: Vector3(x, y, 0), normal: .unitZ, xAxis: .unitX) }

    @Test func theNearestPairIsFoundWhereverItIsInTheList() {
        let points = [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(10, 30, 0), Vector3(51, 0.5, 0), Vector3(80, 80, 0)]
        let nearest = LayoutPreview.nearestDistance(between: points)
        #expect(nearest.map { abs($0 - (1 + 0.25).squareRoot()) < 1e-12 } == true)
        #expect(LayoutPreview.nearestDistance(between: []) == nil)
        #expect(LayoutPreview.nearestDistance(between: [.zero]) == nil)
        #expect(LayoutPreview.nearestDistance(between: [.zero, .zero]) == nil, "points in one place have no distance to size by")
    }

    @Test func aScattersTriadIsAShareOfItsNearestNeighbourNotOfTheStepBetweenConsecutivePoints() {
        // Consecutive points are 30, 20 and 50 apart, but the first and third are 10 apart.
        let planes = [plane(0), plane(30), plane(10, 0), plane(50, 30)]
        #expect(LayoutPreview.triadLength(of: planes) == 8, "0.4 of the closest consecutive step, 20")
        #expect(LayoutPreview.scatterTriadLength(of: planes) == 4, "0.4 of the closest pair, 10")
        #expect(LayoutPreview.scatterTriadLength(of: [plane(0)]) == LayoutPreview.singleTriad)
    }

    func scatterApp() async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let region = builder.add(RectangleNode.self, ["width": .number(60), "height": .number(40)])
        let scatter = builder.add(FieldScatterNode.self, ["minSpacing": .number(8), "maxSpacing": .number(8), "margin": .number(2)])
        builder.wire(region, "profile", to: scatter, "profile")
        return (await makeApp(builder.graph), scatter)
    }

    @Test func aSelectedFieldScatterShowsATriadPerPointAndNoPart() async throws {
        let (app, scatter) = await scatterApp()
        #expect(app.viewport.overlay.isEmpty)
        app.editor.selection = [scatter.id]
        await app.settle()
        let points = app.document.results[scatter.id]?.outputs?["placements"]?.items.count ?? 0
        #expect(points > 15)
        #expect(app.viewport.overlay.lines.count == 3 * points)
        #expect(Set(app.viewport.overlay.lines.map(\.tint)) == [.axisX, .axisY, .axisZ])
        #expect(app.viewport.items.isEmpty, "no part: nothing to pick, frame or open a menu on")
    }

    @Test func theTriadsFollowAnEditAndGoWithTheSelection() async throws {
        let (app, scatter) = await scatterApp()
        app.editor.selection = [scatter.id]
        await app.settle()
        let before = app.viewport.overlay.lines.count
        try app.document.perform(.setInput(scatter.id, "minSpacing", .number(16)))
        try app.document.perform(.setInput(scatter.id, "maxSpacing", .number(16)))
        await app.settle()
        #expect(app.viewport.overlay.lines.count < before)
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }

    @Test func aScatterThatFailsDrawsNothing() async throws {
        let (app, scatter) = await scatterApp()
        try app.document.perform(.setInput(scatter.id, "margin", .number(30)))
        app.editor.selection = [scatter.id]
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }

    @Test func aFieldScatterOnAFaceOutlinesTheClippedAreaDashedBesideItsTriads() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .scatterOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
        await app.settle()
        let scatter = try #require(app.document.graph.nodes.values.first { $0.typeID == FieldScatterNode.typeID })
        #expect(app.document.graph.links.contains { $0.from.node == box.extrude.id && $0.to.node == scatter.id })
        app.editor.selection = [scatter.id]
        await app.settle()
        let points = app.document.results[scatter.id]?.outputs?["placements"]?.items.count ?? 0
        let lines = app.viewport.overlay.lines
        let dashed = lines.filter(\.isDashed)
        #expect(points > 0 && !dashed.isEmpty)
        #expect(dashed.allSatisfy { $0.tint == .construction })
        #expect(lines.count == 3 * points + dashed.count)
    }
}
