/// Something that takes the viewport's primary pointer input while it is set (`ViewportModel.tool`): the sketch
/// editor (sketcher spec §8). The viewport keeps navigation: right-drag orbits, middle-drag pans, scroll and pinch
/// zoom, Shift- and ⌥-drags pan and zoom, and the view cube and handles work as before. Everything else a primary
/// button does is offered to the tool first. Each call carries the camera it was made in.
@MainActor
public protocol ViewportTool: AnyObject {
    /// The pointer moved over the viewport with no drag under way (`nil`: it left the view).
    func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector)
    /// A click off the view cube and the handles. Return true to claim it; unclaimed, the viewport reports the pick
    /// under it as usual (`ViewportEvents.clicked`).
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    /// A primary drag with no navigating modifier (Shift, ⌥) begins at `point`, off the cube and the handles.
    /// Return true to take it: its moves and release then come here, and the camera stays put. Declined, it orbits.
    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
}
