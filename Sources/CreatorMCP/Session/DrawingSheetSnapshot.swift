import CreatorDrawing

/// A sheet as an AI client reads it (DR-5 R19): composed as an export composes it, with what each view's projection had reached.
public struct DrawingSheetSnapshot: Sendable {
    public var picture: SheetPicture
    public var facts: TitleBlockFacts
    public var views: [ViewID: ViewStatus]

    public init(picture: SheetPicture, facts: TitleBlockFacts, views: [ViewID: ViewStatus]) {
        self.picture = picture
        self.facts = facts
        self.views = views
    }
}
