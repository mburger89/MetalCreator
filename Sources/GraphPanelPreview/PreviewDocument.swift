import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The preview's starting document: a bracket-shaped chain with a parameter, one node of each
/// category and an output, laid out left to right.
enum PreviewDocument {
    static let registry = NodeRegistry([
        PreviewNumber.self, PreviewRectangle.self, PreviewExtrude.self, PreviewAllEdges.self,
        PreviewFillet.self, PreviewTransform.self, PreviewGraphParameter.self, PreviewGridPoints.self,
        PreviewOutput.self,
    ])

    @MainActor
    static func make() -> DocumentModel {
        func node(_ definition: any NodeDefinition.Type, _ x: Double, _ y: Double) -> Node {
            registry.makeNode(definition.typeID, at: Vector2(x, y))
        }
        let rect = node(PreviewRectangle.self, 20, 20)
        let extrude = node(PreviewExtrude.self, 240, 20)
        let edges = node(PreviewAllEdges.self, 460, 140)
        let fillet = node(PreviewFillet.self, 680, 20)
        let output = node(PreviewOutput.self, 900, 20)  // `makeNode` flags `.output` nodes as outputs (M3).
        let number = node(PreviewNumber.self, 20, 220)
        func link(_ a: Node, _ s: SocketName, _ b: Node, _ t: SocketName) -> Link {
            Link(from: Endpoint(node: a.id, socket: s), to: Endpoint(node: b.id, socket: t))
        }
        let graph = Graph(
            nodes: Dictionary(uniqueKeysWithValues: [rect, extrude, edges, fillet, output, number].map { ($0.id, $0) }),
            links: [
                link(rect, "profile", extrude, "profile"), link(extrude, "solid", edges, "solid"),
                link(extrude, "solid", fillet, "solid"), link(edges, "edges", fillet, "edges"),
                link(fillet, "solid", output, "solid"),
            ],
            parameters: [GraphParameter(name: "Width", type: .number, value: .number(60), min: 10, max: 200)])
        return DocumentModel(file: GraphFile(graph: graph, viewState: ViewState(dock: .bottom)),
                             registry: registry, kernel: FakeKernel())
    }
}
