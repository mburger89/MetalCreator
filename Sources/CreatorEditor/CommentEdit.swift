import CreatorGraph
import Foundation

/// A comment being typed into in place on the canvas (comments typing plan; spec 2026-10-09 §8): which comment, what it
/// held when editing began (Esc puts it back) and what has been typed since. View state: never undone, never saved.
/// The text reaches the graph only when the edit is committed (`EditorModel.commitCommentEdit()`), as one undo step.
public struct CommentEdit: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A note's multi-line text.
        case noteText
        /// A frame's single-line title.
        case frameTitle
    }

    public var id: CommentID
    public var kind: Kind
    /// What the note's text or the frame's title was when editing began.
    public var original: String
    /// What the field holds now.
    public var draft: String
    /// Names this edit's `PendingEntry`, so only the edit itself can replace or drop it, and the canvas view keys its
    /// field by it (a new edit is a new field, with focus asked for afresh).
    public var owner: UUID
}
