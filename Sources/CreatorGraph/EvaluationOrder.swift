import CreatorKernel

/// Upstream-first order for a demand set, plus any nodes caught in a cycle.
public struct EvaluationOrder: Sendable, Equatable {
    public var order: [NodeID]
    public var cyclic: Set<NodeID>
}
