import CreatorKernel

/// What every level of one evaluation shares (groups spec §5): the registry carrying the document's definitions, so
/// group nodes have their sockets, and the document's parameters.
struct EvaluationSetup: Sendable {
    var registry: NodeRegistry
    var parameters: [ParameterID: ConstantValue]
    /// The level the graph panel shows (`DocumentModel.inspectedLevel`): the group nodes entered from the top level.
    /// Every node of that level is evaluated, whether or not it feeds Group Output, so each shows its state and can
    /// be previewed.
    var inspected: [NodeID] = []

    /// The nodes of `graph`, the inside of the group node at instance path `path`, that the inspected level asks for:
    /// all of them when `path` is the level, else the one group node on the way down to it.
    func inspectedNodes(inside path: [NodeID], of graph: Graph) -> Set<NodeID> {
        guard inspected.starts(with: path) else { return [] }
        return inspected.count == path.count ? Set(graph.nodes.keys) : [inspected[path.count]]
    }
}
