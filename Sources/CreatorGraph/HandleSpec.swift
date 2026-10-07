/// An in-viewport handle that edits a socket (spec §6.5). The viewport resolves its
/// origin and direction from the node's output.
public enum HandleSpec: Sendable, Equatable {
    case linear(SocketName)
    case radial(SocketName)
}
