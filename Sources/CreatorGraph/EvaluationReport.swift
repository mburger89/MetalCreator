import CreatorKernel

public struct EvaluationReport: Sendable {
    public var results: [NodeID: NodeResult]
    /// Nodes that actually ran this time (cache misses), in order.
    public var evaluatedNodes: [NodeID]
}
