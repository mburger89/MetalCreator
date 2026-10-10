/// Which side of a group a socket is on: an input of the group node (an output of Group Input), or an output of the
/// group node (an input of Group Output).
public enum GroupSocketSide: Sendable, Equatable {
    case input, output
}
