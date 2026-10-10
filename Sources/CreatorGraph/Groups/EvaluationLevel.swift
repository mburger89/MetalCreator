import CreatorKernel

/// What one level of an evaluation produced, by each node's ID in that level's graph.
struct EvaluationLevel: Sendable {
    var order: [NodeID]
    var results: [NodeID: NodeResult] = [:]
    var keys: [NodeID: CacheKey] = [:]
    /// Nodes that ran (cache misses), in order; a group node counts when anything inside it ran.
    var evaluated: [NodeID] = []
}
