#if canImport(CreatorOCCT)
import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Assemblies on OpenCascade's real tags and hidden-line removal (DR-5 R2, R3): two copies of one part keep their own balloons,
/// and one part hides another on the sheet.
@MainActor
struct DrawingAssemblyOCCTTests {
    /// A producer (a `width` × 30 × 10 box with a Ø6 hole through it), an Output taking its own solid, and two Outputs taking it
    /// moved by `moves` (two copies of one part: identical tags).
    struct Twins {
        var builder = GraphBuilder()
        var rectangle: Node
        var own: Node
        var twins: [Node] = []

        init(width: Double, moves: [Double]) {
            let rectangle = builder.add(RectangleNode.self, ["width": .number(width), "height": .number(30)])
            let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)])
            let hole = builder.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(0, 0, -1)))])
            let holeSolid = builder.add(ExtrudeNode.self, ["distance": .number(12)])
            let subtract = builder.add(BooleanNode.self, ["operation": .integer(1)])
            builder.wire(rectangle, "profile", to: extrude, "profile")
            builder.wire(hole, "profile", to: holeSolid, "profile")
            builder.wire(extrude, "solid", to: subtract, "target")
            builder.wire(holeSolid, "solid", to: subtract, "tools")
            var first = builder.add(OutputNode.self)
            first.name = "Original"
            builder.replace(first)
            builder.wire(subtract, "solid", to: first, "solid")
            for (index, x) in moves.enumerated() {
                let move = builder.add(TransformNode.self, ["move": .vector(Vector3(x, 0, 0))])
                var output = builder.add(OutputNode.self)
                output.name = "Twin \(index + 1)"
                builder.replace(output)
                builder.wire(subtract, "solid", to: move, "solid")
                builder.wire(move, "solid", to: output, "solid")
                twins.append(output)
            }
            (self.rectangle, own) = (rectangle, first)
        }
    }

    @Test func twinPartsKeepTheirBalloons() async throws {
        let parts = Twins(width: 40, moves: [70, 140])
        let app = await AppModel.inDrawing(parts.builder.graph, kernel: OCCTKernel())
        let view = try #require(await app.placeAssemblyView())
        let content = try #require(app.drawing.editor.contents[view])
        #expect(content.parts.count == 3 && content.problem == nil, "\(content.problem ?? "")")
        let ids = parts.twins.map(\.id)
        let balloons = try ids.map { try app.addBalloon(on: $0, in: view) }
        await app.settle()
        func feet() -> [Double] {
            balloons.compactMap { id -> Double? in
                guard case .leaders(let points)? = app.report(of: id)?.current?.figure else { return nil }
                return points.first?.x
            }
        }
        for id in balloons { #expect(app.report(of: id)?.status == .held, "\(app.report(of: id)?.status as Any)") }
        let before = feet()
        #expect(before.count == 2 && abs((before[1] - before[0]).magnitude - 70) < 1e-3, "each balloon on its own twin: \(before)")
        try app.document.perform(.setInput(parts.rectangle.id, "width", .number(50)), name: "Width")
        await app.settle()
        for id in balloons { #expect(app.report(of: id)?.status == .held, "both held after a width change") }
        let after = feet()
        #expect(after.count == 2 && abs((after[1] - after[0]).magnitude - 70) < 1e-3, "and not on each other's: \(after)")
    }

    @Test func partsHideEachOtherOnTheSheet() async throws {
        var builder = GraphBuilder()
        let (largeRectangle, _, _) = builder.box(distance: 10)
        builder.graph.nodes[largeRectangle.id]?.inputValues["width"] = .number(40)
        builder.graph.nodes[largeRectangle.id]?.inputValues["height"] = .number(30)
        let (smallRectangle, smallExtrude) = builder.solid(distance: 10)
        builder.graph.nodes[smallRectangle.id]?.inputValues["width"] = .number(10)
        builder.graph.nodes[smallRectangle.id]?.inputValues["height"] = .number(10)
        // The small one lies below the large one, so a view from above sees it through the large one.
        let move = builder.add(TransformNode.self, ["move": .vector(Vector3(0, 0, -30))])
        var behind = builder.add(OutputNode.self)
        behind.name = "Behind"
        builder.replace(behind)
        builder.wire(smallExtrude, "solid", to: move, "solid")
        builder.wire(move, "solid", to: behind, "solid")
        let app = await AppModel.inDrawing(builder.graph, kernel: OCCTKernel())
        let view = try #require(await app.placeAssemblyView())
        try await app.editView(view) {
            $0.orientation = .standard(.top)
            $0.showsHidden = true
        }
        let content = try #require(app.drawing.editor.contents[view])
        #expect(content.parts.count == 2 && content.problem == nil, "\(content.problem ?? "")")
        let hidden = content.projection?.lines.filter { $0.visibility == .hidden } ?? []
        #expect(!hidden.isEmpty, "the back part's edges are hidden by the front part")
        #expect(app.drawing.editor.picture?.strokes.contains { $0.layer == .hidden && $0.view == view } == true)
    }
}
#endif
