import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A handle on a per-node socket (`inputs(for:)`, as an exposed sketch dimension is one; S4 → S5 handoff) is shown
/// with its default, and dragging it to the value it already reads records nothing.
@MainActor
struct PerNodeHandleTests {
    func makeGraph() -> (graph: Graph, node: Node) {
        let registry = PerNodeHandleTestNode.registry
        let rectangle = registry.makeNode(RectangleNode.typeID)
        let node = registry.makeNode(PerNodeHandleTestNode.typeID, at: Vector2(240, 0))
        var graph = Graph()
        graph.nodes[rectangle.id] = rectangle
        graph.nodes[node.id] = node
        graph.links.append(Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: node.id, socket: "profile")))
        return (graph, node)
    }

    @Test func aPerNodeSocketsHandleShowsItsDefaultAndEditsIt() async throws {
        let (graph, node) = makeGraph()
        let app = AppModel(kernel: FakeKernel(), registry: PerNodeHandleTestNode.registry, file: GraphFile(graph: graph))
        app.previewMode = .selectedNode
        app.editor.selection = [node.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first)
        #expect(handle.value == 8 && handle.range == 0...50, "the per-node socket's default and range")
        app.handleChanged(handle.id, 8, .ended)
        #expect(!app.document.canUndo, "dragging to the value it already reads records nothing")
        app.handleChanged(handle.id, 12, .ended)
        #expect(app.document.graph.nodes[node.id]?.inputValues["size"] == .number(12))
    }
}
