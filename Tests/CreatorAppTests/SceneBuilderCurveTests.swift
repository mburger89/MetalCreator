import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A curve on an Output node's `curve` output is one curve item in the scene (NURBS spec): faceless, in the scene's bounds.
@MainActor
struct SceneBuilderCurveTests {
    @Test func anOutputWithACurveGivesOneCurveItem() async throws {
        let curve = try await FakeKernel().makeCurve([.line(Vector3(0, 0, 0), Vector3(0, 0, 30))],
                                                     tag: NodeTag(node: NodeID(), item: 0))
        let output = BuiltInNodes.registry.makeNode(OutputNode.typeID)
        let graph = Graph(nodes: [output.id: output])
        let items = SceneBuilder.items(of: output, outputs: ["curve": .list([.curve(curve)])], isGhost: false, graph: graph)
        #expect(items.count == 1)
        let item = try #require(items.first?.item)
        #expect(item.isCurve && !item.isGhost)
        #expect(item.solid.topology.faces.isEmpty)
        #expect(item.solid.bounds == curve.bounds)
        #expect(item.solid.displayedMesh?.edgePolylines[EdgeID(0)] == curve.polyline)
        #expect(items.first?.source == Endpoint(node: output.id, socket: "curve"))
    }
}
