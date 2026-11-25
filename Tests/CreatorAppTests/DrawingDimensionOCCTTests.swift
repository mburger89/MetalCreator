#if canImport(CreatorOCCT)
import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Dimensions on OpenCascade's real edges and tags (drawings plan R4, R12, Task 14): a width change moves the number, a feature that
/// takes the edge loses it, a collinear split keeps it, and a counterbore is called out from its real faces.
@MainActor
struct DrawingDimensionOCCTTests {
    /// A box into an Output over OpenCascade, in Drawing mode with its front view.
    func start(_ builder: GraphBuilder) async throws -> (AppModel, ViewID) {
        let app = await AppModel.inDrawing(builder.graph, kernel: OCCTKernel())
        let view = try #require(await app.placeBaseView())
        return (app, view)
    }

    @Test func aDimensionFollowsAWidthChange() async throws {
        let box = DrawingBox(width: 40)
        let (app, view) = try await start(box.builder)
        let id = try #require(await app.dimensionBottomEdge(of: view))
        #expect(app.texts(of: id).contains("40"), "\(app.texts(of: id))")
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(60)), name: "Width")
        await app.settle()
        #expect(app.texts(of: id).contains("60"), "\(app.texts(of: id))")
        #expect(app.report(of: id)?.status == .held)
    }

    @Test func aChamferOnTheEdgeLosesTheDimension() async throws {
        var box = DrawingBox(width: 40)
        let edges = box.builder.add(AllEdgesNode.self)
        let chamfer = box.builder.add(ChamferNode.self, ["distance": .number(2)])
        box.builder.wire(box.extrude, "solid", to: edges, "solid")
        box.builder.wire(edges, "edges", to: chamfer, "edges")
        let (app, view) = try await start(box.builder)
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let link = Link(from: Endpoint(node: chamfer.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        try app.document.perform(.connect(link), name: "Chamfer")
        await app.settle()
        let report = try #require(app.report(of: id))
        #expect(report.isLost, "the edge the dimension held was cut away: \(report.status)")
        #expect(app.texts(of: id).contains("40?"), "\(app.texts(of: id))")
    }

    @Test func aRibThatSplitsTheEdgeKeepsIt() async throws {
        var box = DrawingBox(width: 40)
        // A block in front of the box that touches only the bottom-front edge (z = 0, the one the Front view's dimension holds,
        // made before the union) along x -5...5: OpenCascade keeps the edge as three collinear pieces. (A block that shares a
        // face with the box is unified into it and splits nothing.)
        let block = box.builder.add(RectangleNode.self, ["width": .number(10), "height": .number(5),
                                                         "plane": .plane(.through(Vector3(0, -7.5, -5))),
        ])
        let blockSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(5)])
        let union = box.builder.add(BooleanNode.self, ["operation": .integer(0)])
        box.builder.wire(block, "profile", to: blockSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: union, "target")
        box.builder.wire(blockSolid, "solid", to: union, "tools")
        let (app, view) = try await start(box.builder)
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let before = try #require(app.report(of: id)?.current?.values)
        let link = Link(from: Endpoint(node: union.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        try app.document.perform(.connect(link), name: "Union")
        await app.settle()
        guard case .ready(let solids, _, _) = DrawingSession.content(of: box.output.id, in: app.document).state else {
            Issue.record("the union didn't evaluate")
            return
        }
        let frontBottom = try #require(solids.first).topology.edges.filter { edge in
            guard case .line(let start, let end)? = edge.curve else { return false }
            return abs(start.y + 5) < 1e-6 && abs(end.y + 5) < 1e-6 && abs(start.z) < 1e-6 && abs(end.z) < 1e-6
        }
        #expect(frontBottom.count == 3, "the union really splits the edge: \(frontBottom.count) pieces")
        #expect(Topology.runCount(frontBottom) == 1, "and the pieces are one run")
        let report = try #require(app.report(of: id))
        #expect(report.status == .held, "\(report.status)")
        #expect(report.current?.values == before, "it measures the run: the value is unchanged")
    }

    @Test func aHoleCalloutOnARealCounterbore() async throws {
        var box = DrawingBox(width: 40)
        box.builder.graph.nodes[box.rectangle.id]?.inputValues["height"] = .number(30)
        let hole = box.builder.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(0, 0, -1)))])
        let holeSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(12)])
        let bore = box.builder.add(CircleNode.self, ["diameter": .number(11), "plane": .plane(.through(Vector3(0, 0, 4)))])
        let boreSolid = box.builder.add(ExtrudeNode.self, ["distance": .number(10)])
        let first = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        let second = box.builder.add(BooleanNode.self, ["operation": .integer(1)])
        box.builder.wire(hole, "profile", to: holeSolid, "profile")
        box.builder.wire(bore, "profile", to: boreSolid, "profile")
        box.builder.wire(box.extrude, "solid", to: first, "target")
        box.builder.wire(holeSolid, "solid", to: first, "tools")
        box.builder.wire(first, "solid", to: second, "target")
        box.builder.wire(boreSolid, "solid", to: second, "tools")
        let link = Link(from: Endpoint(node: second.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid"))
        box.builder.graph.links.removeAll { $0.to == link.to }
        box.builder.graph.links.append(link)
        let (app, view) = try await start(box.builder)
        let editor = app.drawing.editor
        editor.setOrientation(.top, of: view)
        await app.settle()
        let sheet = try #require(editor.currentSheet.flatMap { editor.document.sheet($0) })
        let projection = try #require(editor.contents[view]?.projection)
        let center = try #require(ViewPlacement.centers(in: sheet)[view])
        let mapping = try #require(
            ViewMapping.of(projection: projection, center: center, scale: (sheet.view(view)?.scale ?? sheet.scale).value))
        editor.press(.holeCallout)
        editor.primaryEnded(at: editor.transform.screenPoint(mapping.sheet(Vector2(5.5, 0))), modifiers: [])
        #expect(editor.picks.count == 1, "\(editor.refusal ?? "no refusal")")
        editor.primaryEnded(at: editor.transform.screenPoint(mapping.sheet(Vector2(14, 11))), modifiers: [])
        await app.settle()
        let callout = try #require(editor.document.sheets[0].annotations.first, "\(editor.refusal ?? "no refusal")")
        let lines = try #require(app.report(of: callout.id)?.current?.lines)
        #expect(lines == ["Ø6 THRU", "⌴Ø11 ↧6"], "\(lines)")
    }
}
#endif
