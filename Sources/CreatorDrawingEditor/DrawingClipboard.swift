import CreatorDrawing

/// What copying put aside (DR-5 R18): the views and annotations as they were, in memory, one per editor. Never the system pasteboard.
public struct DrawingClipboard: Hashable, Sendable {
    /// The sheet they were copied from.
    public var sheet: SheetID
    /// That sheet's scale, which a view that followed it keeps on a sheet of another scale.
    public var sheetScale: DrawingScale
    public var views: [DrawingView]
    public var annotations: [DrawingAnnotation]
    /// How many times this has been pasted; each paste lands (10, -10) mm further.
    public var pastes: Int

    public init(
        sheet: SheetID, sheetScale: DrawingScale, views: [DrawingView], annotations: [DrawingAnnotation], pastes: Int = 0
    ) {
        self.sheet = sheet
        self.sheetScale = sheetScale
        self.views = views
        self.annotations = annotations
        self.pastes = pastes
    }
}
