import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// The canvas's cursor (docs/metalui-gaps.md C7 item 5): a closed hand while a middle-button drag pans, the arrow
/// otherwise.
@MainActor
struct CanvasCursorTests {
    /// A middle press can only pan (it never clicks), so the hand shows from the press.
    @Test func aMiddleDragShowsTheClosedHandUntilItsRelease() {
        let editor = makeEditor([])
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(500, 500))
        #expect(editor.canvasCursor == .grabbing)
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        #expect(editor.canvasCursor == .grabbing)
        #expect(editor.canvasCursor?.pointerStyle == .grabActive)
        editor.middleReleased(from: Vector2(500, 500), at: Vector2(530, 500))
        #expect(editor.canvasCursor == nil)
    }

    @Test func movingWiringAndBoxSelectionKeepTheArrow() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude])
        let body = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: body, to: body)
        editor.pointerDragged(from: body, to: body + Vector2(0, 40))
        #expect(editor.interaction != nil && editor.canvasCursor == nil)
        editor.pointerReleased(from: body, at: body + Vector2(0, 40))
        let socket = editor.screenPoint(of: rect.id, "profile", input: false)
        editor.pointerDragged(from: socket, to: socket)
        editor.pointerDragged(from: socket, to: socket + Vector2(60, 0))
        #expect(editor.interaction != nil && editor.canvasCursor == nil)
        editor.pointerReleased(from: socket, at: Vector2(900, 900))
        editor.pointerDragged(from: Vector2(900, 900), to: Vector2(900, 900), modifiers: .shift)
        editor.pointerDragged(from: Vector2(900, 900), to: Vector2(950, 950), modifiers: .shift)
        #expect(editor.interaction != nil && editor.canvasCursor == nil)
        editor.pointerReleased(from: Vector2(900, 900), at: Vector2(950, 950), modifiers: .shift)
        editor.pointerDragged(from: Vector2(900, 900), to: Vector2(900, 900))
        editor.pointerDragged(from: Vector2(900, 900), to: Vector2(950, 950))
        #expect(editor.interaction != nil && editor.canvasCursor == nil, "a plain drag on empty canvas is a box")
    }

    /// A middle pan that lost its release keeps its hand only until the next primary press.
    @Test func aPanThatLostItsReleaseLosesTheHandAtTheNextPress() {
        let editor = makeEditor([])
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(500, 500))
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(560, 500))
        #expect(editor.canvasCursor == .grabbing)
        editor.click(Vector2(100, 100))
        #expect(editor.canvasCursor == nil)
    }

    @Test func scrollingAndPinchingKeepTheArrow() {
        let editor = makeEditor([])
        editor.scrolled(by: Vector2(0, 30), at: Vector2(100, 100), modifiers: [], phase: .step)
        editor.pinchChanged(magnification: 1.3, centre: Vector2(100, 100))
        #expect(editor.canvasCursor == nil)
    }
}
