import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct CanvasLayersTests {
    @Test func wiresRunBetweenTheirSocketAnchors() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        let wires = CanvasLayers.wires(editor)
        #expect(wires.count == 1)
        #expect(wires.first?.geometry.start == Vector2(168, 120))
        #expect(wires.first?.geometry.end == Vector2(300, 40))
        #expect(wires.first?.color == Palette.dracula.socket(.profile))
    }

    @Test func nodeRowsShowUnwiredValuesOnly() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero, values: ["width": .number(60)])
        let number = testNode(NumberTestNode.self, id: 2, at: Vector2(0, 300))
        let editor = makeEditor([rect, number], [wire(number, "value", rect, "height")])
        let rows = NodeRowModel.rows(for: rect, shape: editor.shape(of: rect), graph: editor.graph, registry: editor.registry)
        #expect(rows.map(\.label) == ["Width", "Height", "Plane", "Anchor", "Profile"])
        #expect(rows.map(\.value) == ["60 mm", nil, "XY", "4", nil])
        #expect(rows.map(\.isInput) == [true, true, true, true, false])
    }
}
