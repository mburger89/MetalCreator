import CreatorGraph
import Foundation
import MetalUI

/// A comment being typed into in place on the canvas (comments typing plan; spec 2026-10-09 §8): which comment, what it
/// held when editing began (Esc puts it back) and what has been typed since. View state: never undone, never saved.
/// The text reaches the graph only when the edit is committed (`EditorModel.commitCommentEdit()`), as one undo step.
public struct CommentEdit: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A note's multi-line text.
        case noteText
        /// A frame's single-line title.
        case frameTitle

        /// What a field of this kind selects when it opens on `text` (MetalUI C25, gap CT-b; spec 2026-10-09 §8 Errata
        /// (C25 adoption)): a title opens with all of it selected, as a rename does, so typing replaces it; a note
        /// opens with the caret at the end of its text, so typing appends.
        public func openingSelection(in text: String) -> TextSelection {
            switch self {
            case .frameTitle: TextSelection(range: text.startIndex..<text.endIndex)
            case .noteText: TextSelection(insertionPoint: text.endIndex)
            }
        }
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
    /// The field's selection: what it opened with (`Kind.openingSelection(in:)`), then what the field last published
    /// back (typing, a click, a double click, shift-arrows, ⌘A, delete). Its indices belong to the text the field held
    /// when it wrote them, so after the draft changes they may be stale; MetalUI reads a stale index safely and
    /// `selectedOffsets` clamps it. `nil` until set. It is not part of the undoable state and writes nothing to the graph.
    public var selection: TextSelection?

    /// The selection as Character offsets into `draft`, both ends clamped into the text (a stale index reads as the end).
    /// A multi-selection reads as its first range, which is the one the field acts on (MetalUI divergences 265, 266);
    /// `nil` when there is no selection.
    public var selectedOffsets: Range<Int>? {
        guard let selection else { return nil }
        let range: Range<String.Index>
        switch selection.indices {
        case .selection(let single): range = single
        case .multiSelection(let set):
            guard let first = set.ranges.first else { return nil }
            range = first
        }
        let count = draft.count
        func offset(_ index: String.Index) -> Int {
            if index <= draft.startIndex { return 0 }
            if index >= draft.endIndex { return count }
            return draft.distance(from: draft.startIndex, to: index)
        }
        let lower = offset(range.lowerBound)
        let upper = offset(range.upperBound)
        return min(lower, upper)..<max(lower, upper)
    }
}
