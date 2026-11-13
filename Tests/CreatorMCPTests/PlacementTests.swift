import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorMCP
import Testing

@MainActor struct PlacementTests {
    @Test func freePositionUsesTheNodeWidth() throws {
        let document = DocumentModel(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let session = DocumentModelSession(document: document)
        var node = BuiltInNodes.registry.makeNode("creator.rectangle")
        node.position = Vector2(100, 0)
        try document.perform(.addNode(node), name: "Add Node")
        #expect(session.freePosition(for: node, in: document.graph).x == 100 + CanvasMetrics.nodeWidth + 40)
    }
}
