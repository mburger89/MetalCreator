import CreatorGeometry

/// Something that takes the viewport's primary pointer input while it is set (`ViewportModel.tool`): the sketch
/// editor (sketcher spec §8). The viewport keeps navigation: right-drag orbits, middle-drag pans, scroll and pinch
/// zoom, Shift- and ⌥-drags pan and zoom, and the view cube and handles work as before, unless the tool asks for
/// `.planar` navigation (`navigation`), which never turns the camera. Everything else a primary button does is
/// offered to the tool first. Each call carries the camera it was made in.
@MainActor
public protocol ViewportTool: AnyObject {
    /// How the camera moves while this tool is set (default: `.free`).
    var navigation: ViewportNavigation { get }
    /// What F frames while this tool is set, instead of the selection or the scene (default: `nil`, the usual).
    var framingBounds: BoundingBox? { get }
    /// The pointer moved over the viewport with no drag under way (`nil`: it left the view).
    func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector)
    /// A click off the view cube and the handles. Return true to claim it; unclaimed, the viewport reports the pick
    /// under it as usual (`ViewportEvents.clicked`).
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    /// A primary drag with no navigating modifier (Shift, ⌥) begins at `point`, off the cube and the handles.
    /// Return true to take it: its moves and release then come here, and the camera stays put. Declined, it orbits
    /// (pans with `.planar` navigation).
    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
}

extension ViewportTool {
    public var navigation: ViewportNavigation { .free }
    public var framingBounds: BoundingBox? { nil }
}
