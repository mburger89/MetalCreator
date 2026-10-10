import Foundation

extension EditorModel {
    /// Records what an inspector field holds after a keystroke (`nil` once it's committed or abandoned). There is one
    /// pending entry at a time: a field typed into while a comment is being typed into on the canvas commits that
    /// edit first, so the two never fight over the same text.
    public func notePendingEntry(_ entry: PendingEntry?) {
        if let edit = commentEdit, let entry, entry.owner != edit.owner { commitCommentEdit() }
        pendingEntry = entry
    }

    /// Drops the pending entry if `owner` recorded it. A field calls this when its draft is reset because the
    /// value changed underneath it (undo, a slider, another command), so the stale text is never committed.
    public func discardPendingEntry(ownedBy owner: UUID) {
        if pendingEntry?.owner == owner { pendingEntry = nil }
    }

    /// Commits the pending entry, once. Return calls it, and so do the moments a typed value would otherwise
    /// be lost: the field losing focus, a canvas press, a selection change, and the app shell before it saves
    /// or exports (M6). MetalUI's fields commit only on Return.
    public func commitPendingEntry() {
        guard let entry = pendingEntry else { return }
        pendingEntry = nil
        entry.apply()
    }
}
