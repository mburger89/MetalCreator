import Foundation
import CreatorGraph

/// Editing the selected comment in the inspector (canvas comments spec 2026-10-09 §7). Each edit is one undo step
/// ("Edit Note", "Edit Frame"); none re-evaluates.
extension EditorModel {
    /// The inspector's comment page: nothing when a node is selected or no comment on the canvas is, the comment to
    /// edit for one, and a count for several.
    var commentPage: CommentPage? {
        guard canvasSelection.nodes.isEmpty else { return nil }
        let comments = canvasSelection.comments.sorted().filter { graph.stickies[$0] != nil || graph.frames[$0] != nil }
        switch comments.count {
        case 0: return nil
        case 1:
            if let note = graph.stickies[comments[0]] { return .note(id: note.id, text: note.text, accent: note.accent) }
            return graph.frames[comments[0]].map { .frame(id: $0.id, title: $0.title, accent: $0.accent) }
        default: return .several(count: comments.count)
        }
    }

    /// Sets a note's text, as one undo step. The inspector commits when its field loses focus; an unchanged
    /// text does nothing.
    public func setNoteText(_ id: CommentID, to text: String) {
        guard var note = graph.stickies[id], note.text != text else { return }
        note.text = text
        commitComment(.setSticky(note))
    }

    /// Sets a frame's title, trimmed, as one undo step. An empty title is refused with a message and changes nothing
    /// (returns false, so the field can show the title again); an unchanged one does nothing.
    @discardableResult
    public func setFrameTitle(_ id: CommentID, to title: String) -> Bool {
        guard var box = graph.frames[id] else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            refuse("A frame needs a title.", node: nil)
            return false
        }
        guard box.title != trimmed else { return true }
        box.title = trimmed
        return commitComment(.setFrame(box))
    }

    /// Sets a note's or a frame's accent, as one undo step.
    public func setCommentAccent(_ id: CommentID, to accent: AccentRole) {
        if var note = graph.stickies[id], note.accent != accent {
            note.accent = accent
            commitComment(.setSticky(note))
        } else if var box = graph.frames[id], box.accent != accent {
            box.accent = accent
            commitComment(.setFrame(box))
        }
    }

    @discardableResult
    private func commitComment(_ command: GraphCommand) -> Bool {
        do {
            try edit(command)
            return true
        } catch {
            refuse(error.message, node: nil)
            return false
        }
    }
}
