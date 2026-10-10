import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The drag in progress on the canvas, decided by what the press landed on (spec §6.2).
public enum CanvasInteraction: Equatable, Sendable {
    /// A middle-button drag (`EditorModel.middleDragged`): moves the view. `startOffset` is the canvas offset at its
    /// press.
    case panning(startOffset: Vector2)
    /// Dragging the selection: every selected item moves together. `start` holds their stored positions when the
    /// drag began; `key` coalesces every step of the drag into one undo step.
    case moving(start: SelectionPositions, key: String)
    /// Dragging a selected comment's bottom-right handle (canvas comments spec 2026-10-09 §7): the top-left stays put
    /// and the size follows the pointer, at least `CommentLayout.minimumSize`. `start` is the comment's stored
    /// rectangle when the drag began; `key` coalesces every step into one undo step.
    case resizing(CommentID, start: CanvasRect, key: String)
    /// An ⌥-drag: ghosts of the whole selection follow the pointer and are added on release.
    case duplicating(start: SelectionPositions, delta: Vector2)
    /// A drag on empty canvas. Corners are display canvas points; `base` is the selection before the drag, which the
    /// box is combined with as `mode` says: the modifiers held as the drag started ask for it (none replaces, ⇧ adds,
    /// ⌘ toggles).
    case boxSelecting(start: Vector2, current: Vector2, base: CanvasSelection, mode: SelectionMode)
    case connecting(WireDrag)
}
