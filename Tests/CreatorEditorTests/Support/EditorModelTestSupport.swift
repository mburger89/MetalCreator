// Test fixture file: building an editor over a test document, and finding points on its canvas.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorEditor

@MainActor
func makeEditor(_ nodes: [Node], _ links: [Link] = [], parameters: [GraphParameter] = [],
                stickies: [StickyNote] = [], frames: [CommentFrame] = [],
                dock: DockSide = .bottom, registry: NodeRegistry = editorTestRegistry) -> EditorModel {
    let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links, parameters: parameters,
                      stickies: Dictionary(uniqueKeysWithValues: stickies.map { ($0.id, $0) }),
                      frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) }))
    let document = DocumentModel(file: GraphFile(graph: graph, viewState: ViewState(dock: dock)),
                                 registry: registry, kernel: FakeKernel())
    return EditorModel(document: document)
}

@MainActor
extension EditorModel {
    /// The screen point `inset` canvas points inside a node's drawn top-left corner (in its body).
    func screenPoint(in node: NodeID, inset: Vector2 = Vector2(20, 40)) -> Vector2 {
        guard let node = graph.nodes[node] else { return .zero }
        return transform.toScreen(frame(of: node).origin + inset)
    }

    /// The screen point of a socket's centre.
    func screenPoint(of node: NodeID, _ socket: SocketName, input: Bool) -> Vector2 {
        let ref = SocketRef(Endpoint(node: node, socket: socket), isInput: input)
        return transform.toScreen(anchor(of: ref) ?? .zero)
    }
}
