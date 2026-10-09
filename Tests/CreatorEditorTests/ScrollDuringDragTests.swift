import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorEditor

/// A scroll or a pinch while a press is dragging on the canvas (holding the button and turning the wheel, or
/// pinching mid-drag) leaves the canvas alone: the drag measures from its press, so a transform changed under it
/// would be undone at its next step (a pan) or move the dragged nodes off the pointer (a move). The scroll is still
/// claimed, so it doesn't reach the viewport.
@MainActor
struct ScrollDuringDragTests {
    @Test func aScrollDuringADragPanIsIgnoredAndTheDragKeepsItsOffset() {
        let editor = makeEditor([])
        editor.pointerPressed(at: Vector2(500, 500))
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        let panned = editor.transform
        #expect(editor.scrolled(by: Vector2(0, 40), at: Vector2(530, 500), modifiers: [], phase: .step))
        #expect(editor.scrolled(by: Vector2(0, 10), at: Vector2(530, 500), modifiers: .command, phase: .step))
        #expect(editor.transform == panned)
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(540, 500))
        #expect(editor.transform == CanvasTransform(offset: panned.offset + Vector2(10, 0), zoom: panned.zoom))
    }

    @Test func aPinchDuringADragIsIgnored() {
        let editor = makeEditor([])
        editor.pointerPressed(at: Vector2(500, 500))
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        let panned = editor.transform
        editor.pinchChanged(magnification: 2, centre: Vector2(300, 300))
        #expect(editor.transform == panned)
    }

    @Test func aScrollAfterTheDragEndsMovesTheCanvasAgain() {
        let editor = makeEditor([])
        editor.pointerPressed(at: Vector2(500, 500))
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        editor.pointerReleased(from: Vector2(500, 500), at: Vector2(530, 500))
        let released = editor.transform
        editor.scrolled(by: Vector2(0, 40), at: Vector2(530, 500), modifiers: [], phase: .step)
        #expect(editor.transform == CanvasTransform(offset: released.offset + Vector2(0, 40), zoom: released.zoom))
    }
}
