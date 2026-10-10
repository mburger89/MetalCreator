import CreatorKernel

extension GraphContent {
    /// The top-level node behind faces tagged with `identity`: that node, or the group node whose inside made them
    /// (they are tagged with a scoped ID, groups spec §5), or `nil` when no node is.
    public func topLevelNode(producing identity: NodeID) -> NodeID? {
        if graph.nodes[identity] != nil { return identity }
        return graph.nodes.values.sorted { $0.id < $1.id }.first { node in
            GroupScopes.inner(of: node, at: [], definitions: definitions).contains(identity)
        }?.id
    }
}
