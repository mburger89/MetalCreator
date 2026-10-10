extension AppModel {
    /// Undo, from the menu bar and the top bar. A typed but uncommitted inspector value is committed first, so
    /// ⌘Z undoes that value rather than the step before it, and the value can't be committed later, after the
    /// undo, where it would clear the redo stack.
    public func undo() {
        editor.commitPendingEntry()
        document.undo()
        editor.refreshLevel()
    }

    /// Redo. A typed value is committed first, as for Undo; it is a new edit, so nothing is left to redo.
    public func redo() {
        editor.commitPendingEntry()
        document.redo()
        editor.refreshLevel()
    }
}
