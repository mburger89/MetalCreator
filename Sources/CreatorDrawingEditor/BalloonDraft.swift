import CreatorDrawing
import CreatorGeometry

/// A balloon that has its target and waits for the placing click (DR-5 R16): the line it names and the model point it was clicked at,
/// from which the foot is found. View state: never saved.
public struct BalloonDraft: Hashable, Sendable {
    public var view: ViewID
    public var anchor: PickedAnchor
    public var hint: Vector2

    public init(view: ViewID, anchor: PickedAnchor, hint: Vector2) {
        self.view = view
        self.anchor = anchor
        self.hint = hint
    }
}
