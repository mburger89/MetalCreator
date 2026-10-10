import CreatorGeometry
import CreatorKernel

/// The drag in progress on the canvas, decided by what the press landed on (spec §6.2).
public enum CanvasInteraction: Equatable, Sendable {
    /// A plain drag on empty canvas: moves the view.
    case panning(startOffset: Vector2)
    /// Dragging the selection: every selected item moves together. `start` holds their stored positions when the
    /// drag began; `key` coalesces every step of the drag into one undo step.
    case moving(start: SelectionPositions, key: String)
    /// An ⌥-drag: ghosts of the whole selection follow the pointer and are added on release.
    case duplicating(start: SelectionPositions, delta: Vector2)
    /// A ⇧-drag on empty canvas. Corners are display canvas points; `base` is the selection
    /// before the drag, which the box adds to.
    case boxSelecting(start: Vector2, current: Vector2, base: Set<NodeID>)
    case connecting(WireDrag)
}
