import CreatorDrawing

/// What the editor tells its host: the host stores a commit and shows the sheet the editor moved to.
public struct DrawingEditorEvents {
    public var committed: @MainActor (DrawingCommit) -> Void
    public var sheetChanged: @MainActor (SheetID?) -> Void

    public init(
        committed: @escaping @MainActor (DrawingCommit) -> Void,
        sheetChanged: @escaping @MainActor (SheetID?) -> Void = { _ in }
    ) {
        self.committed = committed
        self.sheetChanged = sheetChanged
    }
}
