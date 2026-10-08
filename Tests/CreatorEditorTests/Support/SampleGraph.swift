// Test fixture file: a bracket-like sample document shared by the render tests.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorEditor

/// Rectangle → Extrude → All Edges → Fillet, a missing node and a Width parameter.
@MainActor
func sampleEditor(dock: DockSide) -> EditorModel {
    let rect = testNode(RectangleTestNode.self, id: 1, at: Vector2(20, 20))
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(260, 20))
    let edges = testNode(AllEdgesTestNode.self, id: 3, at: Vector2(500, 160))
    let fillet = testNode(FilletTestNode.self, id: 4, at: Vector2(740, 20))
    let missing = Node(id: nodeID(5), typeID: "plugin.gone", name: "Gone", position: Vector2(20, 300))
    let width = GraphParameter(name: "Width", type: .number, value: .number(60), min: 10, max: 200)
    return makeEditor([rect, extrude, edges, fillet, missing], [
        wire(rect, "profile", extrude, "profile"), wire(extrude, "solid", edges, "solid"),
        wire(extrude, "solid", fillet, "solid"), wire(edges, "edges", fillet, "edges"),
    ], parameters: [width], dock: dock)
}
