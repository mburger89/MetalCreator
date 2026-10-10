import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Box select modes (spec 2026-10-09 §3, Errata (A); the user's Gate G answer (b), 2026-10-09): every drag that starts
/// on empty canvas draws a box, and the modifiers held as it starts decide how the box combines with the selection it
/// began with: none replaces it, ⇧ adds, ⌘ toggles each node it covers. Panning is the middle button's
/// (`MiddlePanTests`) and two-finger scroll's (`CanvasScrollTests`).
@MainActor
struct BoxSelectModeTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))
    let c = testNode(NumberTestNode.self, id: 3, at: Vector2(800, 0))
    /// A box over b alone, and one over b and c.
    let start = Vector2(380, -20)
    let overB = Vector2(420, 20)
    let overBC = Vector2(820, 20)

    @Test func aPlainDragReplacesTheSelection() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC)
        #expect(editor.selection == [b.id, c.id])
        #expect(editor.transform == CanvasTransform(), "a plain drag on empty canvas no longer pans")
        editor.drag(Vector2(1200, 300), Vector2(1250, 350))
        #expect(editor.selection.isEmpty, "a box over nothing replaces the selection with nothing")
        #expect(!editor.document.canUndo, "selection is view state")
    }

    @Test func commandBoxTogglesEachNodeItCovers() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC, modifiers: .command)
        #expect(editor.selection == [a.id, c.id])
        #expect(editor.transform.offset == .zero, "a ⌘-drag on empty canvas doesn't pan")
    }

    @Test func shiftBoxAddsAndKeepsWhatItCoversSelected() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC, modifiers: .shift)
        #expect(editor.selection == [a.id, b.id, c.id])
    }

    @Test func commandWinsOverShift() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC, modifiers: [.command, .shift])
        #expect(editor.selection == [a.id, c.id])
    }

    /// Letting go of ⇧ a moment before the button (or pressing ⌘ mid-drag) changes nothing: a box that turned into
    /// "replace" at the end would drop the selection it was adding to.
    @Test func theModeIsTheOneTheDragStartedWith() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id]
        editor.pointerDragged(from: start, to: start, modifiers: .shift)
        editor.pointerDragged(from: start, to: overB, modifiers: .shift)
        editor.pointerDragged(from: start, to: overB + Vector2(1, 0), modifiers: [])
        guard case .boxSelecting(_, _, let base, let mode)? = editor.interaction else {
            Issue.record("expected a box selection"); return
        }
        #expect(base == CanvasSelection(nodes: [a.id]) && mode == .add)
        #expect(editor.selection == [a.id, b.id])
        editor.pointerReleased(from: start, at: overB + Vector2(1, 0), modifiers: .command)
        #expect(editor.selection == [a.id, b.id])
    }

    /// The box is re-applied to the selection it began with at every step, so a node it covers and then leaves
    /// again is as it was.
    @Test func aNodeTheBoxLeavesAgainIsAsItWas() {
        let editor = makeEditor([a, b, c])
        editor.selection = [b.id]
        editor.pointerDragged(from: start, to: start, modifiers: .command)
        editor.pointerDragged(from: start, to: overBC, modifiers: .command)
        #expect(editor.selection == [c.id])
        editor.pointerDragged(from: start, to: Vector2(370, 20), modifiers: .command)
        #expect(editor.selection == [b.id])
        editor.pointerReleased(from: start, at: Vector2(370, 20), modifiers: .command)
        #expect(editor.selection == [b.id])
    }
}
