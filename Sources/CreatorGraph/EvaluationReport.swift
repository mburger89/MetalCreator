import CreatorKernel

public struct EvaluationReport: Sendable {
    /// Top-level results.
    public var results: [NodeID: NodeResult]
    /// Top-level nodes that actually ran this time (cache misses), in order. A group node counts when any node
    /// inside it ran.
    public var evaluatedNodes: [NodeID]
    /// Results inside group nodes (groups spec §5), by instance path: the group nodes from the top level down, then
    /// the inner node's ID.
    public var innerResults: [[NodeID]: NodeResult] = [:]
    /// Inner nodes that actually ran this time, by instance path, in order.
    public var evaluatedInnerNodes: [[NodeID]] = []
}
