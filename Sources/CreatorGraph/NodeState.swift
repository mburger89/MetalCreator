/// What a node's badge shows (spec §4.4).
public enum NodeState: Sendable, Equatable {
    /// Not evaluated, with an optional reason ("Connect or set “profile”.").
    case idle(String?)
    case evaluating
    case ok(duration: Duration)
    case warning(String)
    case error(String)

    /// True for `.ok` and `.warning`: the node produced outputs.
    public var isSuccess: Bool {
        switch self {
        case .ok, .warning: true
        case .idle, .evaluating, .error: false
        }
    }
}
