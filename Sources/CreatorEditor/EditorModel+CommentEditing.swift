import CreatorGeometry
import CreatorGraph
import Foundation

/// Typing into a note or a frame's title in place on the canvas (comments typing plan; spec 2026-10-09 §8). The draft
/// is held here and in the model's one `pendingEntry` slot, so a canvas press, a selection change, undo, saving and
/// every other moment that commits a typed inspector value commits it too, and a field typed into elsewhere commits it
/// first (`notePendingEntry`). A commit goes through `setNoteText` / `setFrameTitle`, the inspector's own paths: one
/// undo step, an empty title refused, an unchanged text recorded as nothing.
extension EditorModel {
    /// The edit and where its field is drawn, or `nil` when nothing is being edited, the comment is gone from the
    /// level shown, or the panel is hidden.
    public var commentEditor: CommentEditor? {
        guard isPanelVisible, let edit = commentEdit, let rect = fieldRect(of: edit) else { return nil }
        return CommentEditor(edit: edit, rect: rect)
    }

    /// Starts editing comment `id` in place: a note's text over the note, a frame's title over its title bar. The
    /// comment becomes the whole selection, and anything typed and not yet committed (in the inspector, or on another
    /// comment) is committed first. Returns false, doing nothing, for a comment that isn't on the level shown, with
    /// the panel hidden, or during a drag.
    @discardableResult
    public func beginEditing(_ id: CommentID) -> Bool {
        guard isPanelVisible, interaction == nil else { return false }
        let kind: CommentEdit.Kind
        let text: String
        if let note = graph.stickies[id] {
            kind = .noteText
            text = note.text
        } else if let box = graph.frames[id] {
            kind = .frameTitle
            text = box.title
        } else {
            return false
        }
        commitPendingEntry()
        canvasSelection = CanvasSelection(comments: [id])
        let edit = CommentEdit(id: id, kind: kind, original: text, draft: text, owner: UUID())
        commentEdit = edit
        pendingEntry = entry(for: edit)
        return true
    }

    /// The field's text changed (every keystroke).
    public func commentDraftChanged(_ text: String) {
        guard var edit = commentEdit, edit.draft != text else { return }
        edit.draft = text
        commentEdit = edit
        pendingEntry = entry(for: edit)
    }

    /// Ends the edit, writing the draft: focus loss, ⌘↩ on a note, Return on a title. Does nothing with no edit.
    public func commitCommentEdit() {
        guard let edit = commentEdit else { return }
        if pendingEntry?.owner == edit.owner {
            commitPendingEntry()
        } else {
            commentEdit = nil
        }
    }

    /// Ends the edit and throws the draft away (Esc): the comment keeps what it held.
    public func cancelCommentEdit() {
        guard let edit = commentEdit else { return }
        if pendingEntry?.owner == edit.owner { pendingEntry = nil }
        commentEdit = nil
    }

    /// The field's rectangle in display canvas points: the note's, or the frame's title bar.
    private func fieldRect(of edit: CommentEdit) -> CanvasRect? {
        switch edit.kind {
        case .noteText: graph.stickies[edit.id].map { frame(of: $0) }
        case .frameTitle: graph.frames[edit.id].map { CommentLayout.titleBar(of: frame(of: $0)) }
        }
    }

    /// The pending entry that stands for `edit`: committing it ends the edit and writes the draft.
    private func entry(for edit: CommentEdit) -> PendingEntry {
        PendingEntry(owner: edit.owner, text: edit.draft, textCommit: { [weak self] text in self?.finishCommentEdit(with: text) })
    }

    /// Writes the draft and ends the edit. A title is one line: line breaks in it (pasted ones) become spaces.
    private func finishCommentEdit(with text: String) {
        guard let edit = commentEdit else { return }
        commentEdit = nil
        switch edit.kind {
        case .noteText: setNoteText(edit.id, to: text)
        case .frameTitle: setFrameTitle(edit.id, to: text.split(whereSeparator: \.isNewline).joined(separator: " "))
        }
    }
}
