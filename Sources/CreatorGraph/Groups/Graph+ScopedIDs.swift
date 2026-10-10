import CreatorKernel

extension Graph {
    /// Every identity this graph's nodes evaluate under, given `definitions`: its own node IDs, and the scoped ID of
    /// every node inside every group node, at every depth (`NodeID.scoped`). The evaluator keeps cache entries of
    /// these and drops the rest.
    func scopedNodeIDs(definitions: [GroupID: GroupDefinition]) -> Set<NodeID> {
        nodes.values.reduce(into: Set(nodes.keys)) { ids, node in
            ids.formUnion(GroupScopes.inner(of: node, at: [], definitions: definitions))
        }
    }
}
