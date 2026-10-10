import CreatorGraph

/// What the inspector shows for the selected comments (canvas comments spec 2026-10-09 §7): the note or frame to edit
/// when exactly one comment is selected and no node, or how many when several are.
public enum CommentPage: Equatable, Sendable {
    case note(id: CommentID, text: String, accent: AccentRole)
    case frame(id: CommentID, title: String, accent: AccentRole)
    case several(count: Int)

    /// "N comments selected" for several, else `nil`.
    public var summary: String? {
        if case .several(let count) = self { return "\(count) comments selected" }
        return nil
    }
}
