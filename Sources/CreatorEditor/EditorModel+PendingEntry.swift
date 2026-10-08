extension EditorModel {
    /// Records what an inspector field holds after a keystroke (`nil` once it's committed or abandoned).
    public func notePendingEntry(_ entry: PendingEntry?) {
        pendingEntry = entry
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
