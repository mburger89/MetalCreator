// Test fixture file: pointer gestures for the editor tests.
import CreatorGeometry
@testable import CreatorEditor

@MainActor
extension EditorModel {
    /// A click (press and release without moving) at a canvas-local screen point, with `modifiers` held
    /// throughout, as the canvas's zero-distance drag reports one.
    func click(_ point: Vector2, modifiers: CanvasModifiers = []) {
        pointerDragged(from: point, to: point, modifiers: modifiers)
        pointerReleased(from: point, at: point, modifiers: modifiers)
    }

    /// A press at `start`, a move to `end` and a release there, with `modifiers` held throughout.
    func drag(_ start: Vector2, _ end: Vector2, modifiers: CanvasModifiers = []) {
        pointerDragged(from: start, to: start, modifiers: modifiers)
        pointerDragged(from: start, to: end, modifiers: modifiers)
        pointerReleased(from: start, at: end, modifiers: modifiers)
    }

    /// A middle-button press at `start`, a move to `end` and a release there, as the canvas's zero-distance middle
    /// drag reports them.
    func middleDrag(_ start: Vector2, _ end: Vector2) {
        middleDragged(from: start, to: start)
        middleDragged(from: start, to: end)
        middleReleased(from: start, at: end)
    }
}
