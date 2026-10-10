import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorEditor

/// A scroll or a pinch while a drag is under way on the canvas (holding a button and turning the wheel, or pinching
/// mid-drag) leaves the canvas alone: the drag measures from its press, so a transform changed under it would be
/// undone at its next step (a middle-button pan), move the dragged nodes off the pointer (a move) or shift a box
/// under it. The scroll is still claimed, so it doesn't reach the viewport.
@MainActor
struct ScrollDuringDragTests {
    @Test func aScrollDuringAMiddlePanIsIgnoredAndThePanKeepsItsOffset() {
        let editor = makeEditor([])
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(500, 500))
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        let panned = editor.transform
        #expect(editor.scrolled(by: Vector2(0, 40), at: Vector2(530, 500), modifiers: [], phase: .step))
        #expect(editor.scrolled(by: Vector2(0, 10), at: Vector2(530, 500), modifiers: .command, phase: .step))
        #expect(editor.transform == panned)
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(540, 500))
        #expect(editor.transform == CanvasTransform(offset: panned.offset + Vector2(10, 0), zoom: panned.zoom))
    }

    @Test func aScrollDuringABoxIsIgnored() {
        let editor = makeEditor([])
        editor.pointerPressed(at: Vector2(500, 500))
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        guard case .boxSelecting? = editor.interaction else { Issue.record("expected a box"); return }
        #expect(editor.scrolled(by: Vector2(0, 40), at: Vector2(530, 500), modifiers: [], phase: .step))
        #expect(editor.transform == CanvasTransform())
    }

    @Test func aPinchDuringADragIsIgnored() {
        let editor = makeEditor([])
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(500, 500))
        editor.middleDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        let panned = editor.transform
        editor.pinchChanged(magnification: 2, centre: Vector2(300, 300))
        #expect(editor.transform == panned)
    }

    @Test func aScrollAfterTheDragEndsMovesTheCanvasAgain() {
        let editor = makeEditor([])
        editor.middleDrag(Vector2(500, 500), Vector2(530, 500))
        let released = editor.transform
        editor.scrolled(by: Vector2(0, 40), at: Vector2(530, 500), modifiers: [], phase: .step)
        #expect(editor.transform == CanvasTransform(offset: released.offset + Vector2(0, 40), zoom: released.zoom))
    }
}
