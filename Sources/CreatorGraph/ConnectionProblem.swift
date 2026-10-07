/// Why a wire can't be made.
public enum ConnectionProblem: Error, Equatable, Sendable {
    case unknownNode
    case unknownSocket(SocketName)
    case sameNode
    case typeMismatch(from: SocketType, to: SocketType)
    case wouldCreateCycle
}
