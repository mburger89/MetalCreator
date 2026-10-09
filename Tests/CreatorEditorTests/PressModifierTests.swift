import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The canvas reads the modifiers from the press itself (MetalUI C7's `DragGesture.Value.modifiers`, spec §6.2):
/// a click reads those held at the press, a drag those held when it starts, and nothing carries over from one
/// press to the next.
@MainActor
struct PressModifierTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))

    @Test func aShiftClickReadsTheModifiersHeldAtThePress() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: point, to: point, modifiers: .shift)
        editor.pointerReleased(from: point, at: point, modifiers: [])
        #expect(editor.selection == [a.id, b.id], "⇧ let go before the release still extends")
    }

    @Test func aShiftPressedOnlyForTheReleaseDoesntExtend() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: point, to: point, modifiers: [])
        editor.pointerReleased(from: point, at: point, modifiers: .shift)
        #expect(editor.selection == [b.id])
    }

    /// A press that reports only its end (no change first) reads the release's modifiers.
    @Test func aClickWithNoChangeReadsItsReleasesModifiers() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerReleased(from: point, at: point, modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
    }

    @Test func aModifierHeldForOnePressDoesntCarryIntoTheNext() {
        let editor = makeEditor([a, b])
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        editor.drag(Vector2(600, 600), Vector2(640, 620))
        #expect(editor.transform.offset == Vector2(40, 20), "a plain drag on empty canvas pans, not box-selects")
    }

    /// ⌥ pressed after the button went down, but before the press moved far enough to drag, still duplicates.
    @Test func optionPressedBeforeTheDragStartsDuplicates() {
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: [])
        editor.pointerDragged(from: start, to: start + Vector2(1, 0), modifiers: .option)
        #expect(editor.interaction == nil)
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        guard case .duplicating? = editor.interaction else { Issue.record("expected ghosts"); return }
    }

    /// What a drag does is decided when it starts; a modifier pressed later doesn't change it.
    @Test func aModifierPressedMidDragDoesntChangeTheDrag() {
        let editor = makeEditor([a])
        editor.pointerDragged(from: Vector2(600, 600), to: Vector2(600, 600))
        editor.pointerDragged(from: Vector2(600, 600), to: Vector2(620, 600))
        editor.pointerDragged(from: Vector2(600, 600), to: Vector2(650, 600), modifiers: .shift)
        guard case .panning? = editor.interaction else { Issue.record("expected a pan"); return }
        #expect(editor.transform.offset == Vector2(50, 0))
    }

    /// A press whose release was lost (the window resigned mid-drag) takes its ⇧ with it.
    @Test func aLostPressTakesItsModifiersWithIt() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: .shift)
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
    }
}
