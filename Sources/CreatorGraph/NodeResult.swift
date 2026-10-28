/// A node's state and, on success, its outputs.
public struct NodeResult: Sendable {
    public var state: NodeState
    public var outputs: [SocketName: Value]?
    /// What the node declared while it ran, every iteration's in order. Empty when it failed.
    public var dimensions: [DimensionSpec] = []

    public init(state: NodeState, outputs: [SocketName: Value]? = nil, dimensions: [DimensionSpec] = []) {
        self.state = state
        self.outputs = outputs
        self.dimensions = dimensions
    }

    public var estimatedBytes: Int { (outputs ?? [:]).values.reduce(64) { $0 + $1.estimatedBytes } }
}
