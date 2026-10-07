/// A node's own failure, with a message for the person editing the graph.
public enum NodeError: Error, Equatable, Sendable {
    case missingInput(SocketName)
    case typeMismatch(SocketName, expected: SocketType)
    case invalidValue(String)

    public var message: String {
        switch self {
        case .missingInput(let socket): "Connect or set “\(socket)”."
        case .typeMismatch(let socket, let expected): "“\(socket)” needs a \(expected.rawValue)."
        case .invalidValue(let message): message
        }
    }
}
