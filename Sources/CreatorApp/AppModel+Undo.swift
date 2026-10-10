extension AppModel {
    /// The Edit menu's and the top bar's Undo title: "Undo Add Note" for the step Undo would take back, plain "Undo"
    /// with nothing to undo (as macOS apps read). The names are `UndoName`s, in English and never saved.
    public var undoTitle: String { Self.title("Undo", step: document.undoName) }

    /// The Redo title: "Redo Add Note", or plain "Redo" with nothing to redo.
    public var redoTitle: String { Self.title("Redo", step: document.redoName) }

    private static func title(_ verb: String, step: String?) -> String {
        step.map { "\(verb) \($0)" } ?? verb
    }

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
