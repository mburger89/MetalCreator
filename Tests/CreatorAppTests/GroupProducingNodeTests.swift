import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A face made inside a group is tagged with a scoped ID (groups spec §5); "Show Producing Node" shows its group node.
@MainActor
struct GroupProducingNodeTests {
    @Test func aFaceMadeInsideAGroupShowsItsGroupNode() async throws {
        let registry = BuiltInNodes.registry
        var rib = GroupDefinition.make(name: "Rib", outputs: [SocketSpec("solid", .solid)], registry: registry)
        let rectangle = registry.makeNode(RectangleNode.typeID), extrude = registry.makeNode(ExtrudeNode.typeID)
        rib.graph.nodes[rectangle.id] = rectangle
        rib.graph.nodes[extrude.id] = extrude
        if let output = rib.outputNode {
            rib.graph.links = [
                Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: extrude.id, socket: "profile")),
                Link(from: Endpoint(node: extrude.id, socket: "solid"), to: Endpoint(node: output.id, socket: "solid")),
            ]
        }
        var node = registry.withGroups([rib.id: rib]).makeGroupNode(GroupNodes.groupTypeID, for: rib.id, at: Vector2(600, 400))
        node.isOutput = true
        let file = GraphFile(graph: Graph(nodes: [node.id: node]), definitions: [rib.id: rib], viewState: ViewState(dock: .hidden))
        let app = AppModel(kernel: FakeKernel(), file: file)
        await app.settle()

        let scoped = NodeID.scoped([node.id, extrude.id])
        guard case .solid(let solid)? = app.document.results[node.id]?.outputs?["solid"]?.items.first else {
            Issue.record("expected the group's solid")
            return
        }
        #expect(solid.topology.faces.allSatisfy { face in face.tags.allSatisfy { $0.node == scoped } })
        #expect(app.viewport.events.nodeName(scoped) == "Rib")
        app.showProducingNode(scoped)
        #expect(app.editor.selection == [node.id])
        #expect(app.editor.isPanelVisible)
        #expect(app.viewport.events.nodeName(NodeID()) == nil)
    }
}
