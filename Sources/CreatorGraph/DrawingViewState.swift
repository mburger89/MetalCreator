import CreatorDrawing

/// Whether the window is in Drawing mode and which sheet it shows, saved in `ViewState.drawing` (DR-1, plan R4). The sheet's pan and
/// zoom are not saved. Switching mode or sheet is view state: never an edit and never an undo step.
public struct DrawingViewState: Hashable, Sendable, Codable {
    public var isOn: Bool
    public var sheet: SheetID?

    public init(isOn: Bool = false, sheet: SheetID? = nil) {
        self.isOn = isOn
        self.sheet = sheet
    }
}
