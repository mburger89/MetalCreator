import CreatorGeometry

/// A pointer drag in progress: what it does, where it started, and what it started from.
struct DragState {
    var mode: ViewportDragMode
    /// The button that began it: only that button's moves and release reach it.
    var button: ViewportPointerButton
    var start: ScreenPoint
    var last: ScreenPoint
    var startPose: CameraPose
    /// The orbit pivot: the model point under the press, else the bounds centre.
    var pivot: Vector3?
    var handleStartValue: Double
    /// The modifiers held at the press, passed to a tool's drag.
    var modifiers: ViewportModifiers = []
}
