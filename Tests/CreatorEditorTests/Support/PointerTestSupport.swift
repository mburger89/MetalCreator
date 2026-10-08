// Test fixture file: pointer gestures for the editor tests.
import CreatorGeometry
@testable import CreatorEditor

@MainActor
extension EditorModel {
    /// A click (press and release without moving) at a canvas-local screen point.
    func click(_ point: Vector2) {
        pointerDragged(from: point, to: point)
        pointerReleased(from: point, at: point)
    }

    /// A press at `start`, a move to `end` and a release there.
    func drag(_ start: Vector2, _ end: Vector2) {
        pointerDragged(from: start, to: start)
        pointerDragged(from: start, to: end)
        pointerReleased(from: start, at: end)
    }
}
