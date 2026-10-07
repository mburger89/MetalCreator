/// A node's state and, on success, its outputs.
public struct NodeResult: Sendable {
    public var state: NodeState
    public var outputs: [SocketName: Value]?

    public init(state: NodeState, outputs: [SocketName: Value]? = nil) {
        self.state = state
        self.outputs = outputs
    }

    public var estimatedBytes: Int { (outputs ?? [:]).values.reduce(64) { $0 + $1.estimatedBytes } }
}
