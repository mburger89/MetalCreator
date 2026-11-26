import CreatorDrawing

/// What the editor tells its host: the host stores a commit and shows the sheet the editor moved to.
public struct DrawingEditorEvents {
    public var committed: @MainActor (DrawingCommit) -> Void
    public var sheetChanged: @MainActor (SheetID?) -> Void
    /// A cancelled drag took back the steps it had committed under this coalescing key (plan R18): the host drops them from its
    /// undo stack.
    public var discarded: @MainActor (String) -> Void

    public init(
        committed: @escaping @MainActor (DrawingCommit) -> Void,
        sheetChanged: @escaping @MainActor (SheetID?) -> Void = { _ in },
        discarded: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.committed = committed
        self.sheetChanged = sheetChanged
        self.discarded = discarded
    }
}
