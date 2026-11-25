import Foundation

/// Text typed into an inspector field and not yet submitted: the field notes it here as it is typed, so a moment that would
/// otherwise lose it (Save, Undo, an export, a mode switch, the close request) can commit it first, as `EditorModel` does for the
/// graph's inspector.
struct PendingDraft {
    let owner: UUID
    let apply: @MainActor () -> Void
}

extension DrawingEditorModel {
    /// A field records its draft. Another field's draft still waiting is committed first, so none is lost.
    func notePendingDraft(owner: UUID, apply: @escaping @MainActor () -> Void) {
        if let pending = pendingDraft, pending.owner != owner { commitPendingEntry() }
        pendingDraft = PendingDraft(owner: owner, apply: apply)
    }

    /// Drops the draft if `owner` recorded it (the field submitted it, or its value changed underneath it).
    func discardPendingDraft(ownedBy owner: UUID) {
        if pendingDraft?.owner == owner { pendingDraft = nil }
    }

    /// Submits the typed text, once. Called by every moment a draft would otherwise be lost.
    public func commitPendingEntry() {
        guard let pending = pendingDraft else { return }
        pendingDraft = nil
        pending.apply()
    }
}
