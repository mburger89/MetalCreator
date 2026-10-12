import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import CreatorViewport
import Testing
@testable import CreatorApp

/// A selected layout node shows its placements as small axis triads (patterns spec §8), Face Pattern also its clipped area:
/// an overlay, so nothing about it picks, frames or opens a menu. What it looks like is a human check (group PL).
@MainActor
struct LayoutPreviewTests {
    func plane(_ x: Double) -> Plane { Plane(origin: Vector3(x, 0, 0), normal: .unitZ, xAxis: .unitX) }

    // MARK: Triads

    @Test func eachPlacementGetsAnXAYAndAZLineInTheAxisTints() {
        let lines = LayoutPreview.triads(of: [plane(0), plane(10)])
        #expect(lines.count == 6)
        #expect(lines.prefix(3).map(\.tint) == [.axisX, .axisY, .axisZ])
        #expect(lines[0].a == .zero && lines[0].b == Vector3(4, 0, 0), "along x, a share of the 10 mm between placements")
        #expect(lines[1].b == Vector3(0, 4, 0) && lines[2].b == Vector3(0, 0, 4))
        #expect(lines[3].a == Vector3(10, 0, 0))
    }

    @Test func aLoneTriadHasAFixedSizeAndPlacementsInOnePlaceDoNotCollapseIt() {
        #expect(LayoutPreview.triadLength(of: [plane(0)]) == LayoutPreview.singleTriad)
        #expect(LayoutPreview.triadLength(of: [plane(3), plane(3)]) == LayoutPreview.singleTriad)
        #expect(LayoutPreview.triadLength(of: []) == LayoutPreview.singleTriad)
    }

    @Test func triadsAreSizedByTheClosestNeighboursNotTheRowBreaks() {
        // Two rows of two, 10 apart in a row but 100 between the rows.
        let planes = [plane(0), plane(10), Plane(origin: Vector3(10, 100, 0), normal: .unitZ, xAxis: .unitX),
                      Plane(origin: Vector3(20, 100, 0), normal: .unitZ, xAxis: .unitX),
        ]
        #expect(LayoutPreview.triadLength(of: planes) == 4)
    }

    // MARK: In the app

    func linearApp(_ settings: [SocketName: ConstantValue] = [:]) async -> (AppModel, Node, Node) {
        var builder = GraphBuilder()
        let layout = builder.add(LinearPatternNode.self, settings)
        let other = builder.add(NumberNode.self)
        return (await makeApp(builder.graph), layout, other)
    }

    @Test func aSelectedLayoutNodeShowsItsPlacementsEvenBeforeAnythingIsWiredToIt() async throws {
        let (app, layout, _) = await linearApp(["count": .integer(4), "spacing": .number(10)])
        #expect(app.viewport.overlay.isEmpty, "nothing selected")
        app.editor.selection = [layout.id]
        await app.settle()
        let lines = app.viewport.overlay.lines
        #expect(lines.count == 12 && Set(lines.map(\.tint)) == [.axisX, .axisY, .axisZ])
        #expect(app.viewport.items.isEmpty, "the triads are no part of the scene: nothing to pick, frame or open a menu on")
        #expect(app.viewport.overlay.points.isEmpty && app.viewport.overlay.fills.isEmpty && app.viewport.overlay.gridPlane == nil)
    }

    @Test func theTriadsFollowAnEditAndGoWhenAnotherNodeOrNothingIsSelected() async throws {
        let (app, layout, other) = await linearApp(["count": .integer(2)])
        app.editor.selection = [layout.id]
        await app.settle()
        #expect(app.viewport.overlay.lines.count == 6)
        try app.document.perform(.setInput(layout.id, "count", .integer(5)))
        await app.settle()
        #expect(app.viewport.overlay.lines.count == 15)
        app.editor.selection = [other.id]
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
        app.editor.selection = [layout.id, other.id]
        await app.settle()
        #expect(app.viewport.overlay.isEmpty, "only one selected node is previewed")
        app.editor.selection = [layout.id]
        await app.settle()
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }

    @Test func aLayoutNodeInErrorShowsNothing() async throws {
        let (app, layout, _) = await linearApp(["count": .integer(-1)])
        app.editor.selection = [layout.id]
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }

    @Test func theShortcutsAndPlaceShowNothingOfTheirOwn() async throws {
        var builder = GraphBuilder()
        let place = builder.add(PlaceNode.self)
        let app = await makeApp(builder.graph)
        app.editor.selection = [place.id]
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }

    @Test func aCircularPatternShowsOneTriadPerPlacementInEveryRing() async throws {
        var builder = GraphBuilder()
        let ring = builder.add(CircularPatternNode.self, ["count": .integer(6), "rings": .integer(2)])
        let app = await makeApp(builder.graph)
        app.editor.selection = [ring.id]
        await app.settle()
        #expect(app.viewport.overlay.lines.count == 36)
    }

    // MARK: Face Pattern

    @Test func aFacePatternAlsoOutlinesTheAreaItFillsWithDashedLines() async throws {
        var builder = GraphBuilder()
        let plate = builder.box(distance: 6, at: .zero)
        let pattern = builder.add(FacePatternNode.self, ["margin": .number(3)])
        builder.wire(plate.extrude, "solid", to: pattern, "solid")
        var graph = builder.graph
        graph.nodes[plate.rectangle.id]?.inputValues["width"] = .number(60)
        graph.nodes[plate.rectangle.id]?.inputValues["height"] = .number(40)
        // Pick the plate's top face on a first run, as the face menu would.
        let solid = try await solid(of: plate.extrude, in: graph)
        let top = try #require(solid.topology.faces.first { $0.kind == .plane && $0.normal == .unitZ })
        graph.nodes[pattern.id]?.inputValues[NodeSetting.face] = .facePick(try #require(solid.topology.facePick(for: top.id)))
        let app = await makeApp(graph, kernel: OCCTKernel())
        app.editor.selection = [pattern.id]
        await app.settle()
        let lines = app.viewport.overlay.lines
        let dashed = lines.filter(\.isDashed)
        #expect(dashed.count == 4 && dashed.allSatisfy { $0.tint == .construction })
        let corners = Set(dashed.map { Vector2(($0.a.x * 1e3).rounded() / 1e3, ($0.a.y * 1e3).rounded() / 1e3) })
        #expect(corners == [Vector2(-27, -17), Vector2(27, -17), Vector2(27, 17), Vector2(-27, 17)], "\(corners)")
        #expect(dashed.allSatisfy { abs($0.a.z - 6) < 1e-6 && abs($0.b.z - 6) < 1e-6 }, "on the face, 6 mm up")
        let triads = lines.filter { !$0.isDashed }
        #expect(!triads.isEmpty && triads.count % 3 == 0, "and the triads of its placements")
    }

    func solid(of node: Node, in graph: Graph) async throws -> Solid {
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: OCCTKernel()).evaluate(graph, demand: [node.id])
        return try #require(report.results[node.id]?.outputs?["solid"]?.items.compactMap { scalar -> Solid? in
            if case .solid(let solid) = scalar { solid } else { nil }
        }.first)
    }
}
