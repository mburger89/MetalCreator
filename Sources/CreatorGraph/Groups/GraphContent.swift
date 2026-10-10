/// Everything graph commands edit (groups spec §4, §5): the top-level graph and the document's group definitions.
/// `apply(_:registry:)` (`GraphContent+Apply`) is how `DocumentModel` changes either.
public struct GraphContent: Sendable, Equatable {
    public var graph: Graph
    public var definitions: [GroupID: GroupDefinition]

    public init(graph: Graph = Graph(), definitions: [GroupID: GroupDefinition] = [:]) {
        self.graph = graph
        self.definitions = definitions
    }

    /// The graph at `path`, or `nil` for a definition that doesn't exist.
    public func graph(at path: GraphPath) -> Graph? {
        switch path {
        case .root: graph
        case .definition(let id): definitions[id]?.graph
        }
    }
}
