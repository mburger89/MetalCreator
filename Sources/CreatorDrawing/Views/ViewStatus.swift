/// Whether a view's lines are current (DR-5 R19): what the MCP's `get_sheet` says of each view.
public enum ViewStatus: Hashable, Sendable {
    /// Its projection has landed and holds nothing wrong.
    case drawn
    /// Its projection is still being made; the lines shown are the previous ones.
    case pending
    /// It couldn't be drawn; the sentence says why (the previous lines, if any, stay faded).
    case failed(String)

    /// The status of a view from the content the editor holds for it.
    public init(_ content: ViewContent) {
        if content.isPending {
            self = .pending
        } else if let problem = content.problem {
            self = .failed(problem)
        } else {
            self = .drawn
        }
    }
}
