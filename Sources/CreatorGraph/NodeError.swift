/// A node's own failure, with a message for the person editing the graph.
public enum NodeError: Error, Equatable, Sendable {
    case missingInput(SocketName)
    case typeMismatch(SocketName, expected: SocketType)
    case invalidValue(String)

    public var message: String {
        switch self {
        case .missingInput(let socket): "Connect or set “\(socket)”."
        case .typeMismatch(let socket, let expected): "“\(socket)” needs \(expected.indefiniteName)."
        case .invalidValue(let message): message
        }
    }
}

/// A node's failure that still has something to show: `recovery` is kept on its `NodeResult` beside the error state (never wired
/// downstream: the node has failed). Trim Surface uses it to keep its `pieces` when every picked region has vanished, so the
/// regions can be picked again.
public struct NodeFailure: Error, Sendable {
    public var message: String
    public var recovery: [SocketName: Value]

    public init(_ message: String, recovery: [SocketName: Value]) {
        self.message = message
        self.recovery = recovery
    }
}
