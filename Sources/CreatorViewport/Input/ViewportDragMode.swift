/// What a pointer drag in the viewport does, decided when it starts.
public enum ViewportDragMode: Hashable, Sendable {
    case orbit
    case pan
    case zoom
    /// The drag began on the view cube: it orbits, and a click selects a cube region.
    case cube
    /// The drag began on a handle's knob: it edits that handle (by `ViewportHandle.id`).
    case handle(String)
}
