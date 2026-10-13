import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// A press MetalUI dropped without a release (`onCancelled`, C16, docs/metalui-gaps.md VI-a: another press replaced it,
/// or a release went unseen) ends as Esc ends a drag, once and for good: it never clicks, and what it had started is put
/// back or finished by what it already did.
@MainActor
struct PointerCancelTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(300, 0))
    let a = testNode(NumberTestNode.self, id: 4, at: Vector2(0, 300))
    let b = testNode(NumberTestNode.self, id: 5, at: Vector2(300, 300))

    @Test func aCancelledWireDragDropsTheWireAndConnectsNothing() {
        let editor = makeEditor([rect, extrude])
        let start = editor.screenPoint(of: rect.id, "profile", input: false)
        let target = editor.screenPoint(of: extrude.id, "profile", input: true)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: target)
        #expect(editor.interaction != nil)
        editor.pointerCancelled()
        #expect(editor.interaction == nil && editor.graph.links.isEmpty)
        editor.pointerReleased(from: start, at: target)
        #expect(editor.graph.links.isEmpty, "the release that never came and then did, finds no press")
    }

    @Test func aCancelledBoxPutsBackTheSelectionItBeganWith() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let corner = Vector2(-20, 250)
        editor.pointerDragged(from: corner, to: corner)
        editor.pointerDragged(from: corner, to: Vector2(500, 500))
        #expect(editor.selection == [a.id, b.id], "the box covers both")
        editor.pointerCancelled()
        #expect(editor.selection == [a.id] && editor.interaction == nil)
    }

    @Test func aCancelledOptionDragLeavesNoCopies() {
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 80), modifiers: .option)
        editor.pointerCancelled()
        #expect(editor.graph.nodes.count == 1 && editor.interaction == nil)
    }

    /// A move's steps are already in the document, so a cancel keeps them and closes their undo step: the next edit is
    /// another one.
    @Test func aCancelledMoveStaysWhereItGotToAsOneUndoStep() {
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(40, 0))
        editor.pointerDragged(from: start, to: start + Vector2(80, 0))
        let moved = editor.graph.nodes[a.id]?.position
        editor.pointerCancelled()
        #expect(moved != Vector2(0, 300) && editor.graph.nodes[a.id]?.position == moved)
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 300), "one undo step takes the whole move back")
        #expect(!editor.document.canUndo)
    }

    /// Review Focus 4: a press cancelled before it moved is no click, and no first half of a double click.
    @Test func aCancelledPressIsNoClickAndNoHalfOfADoubleClick() {
        let sketch = testNode(SketchTestNode.self, id: 1, at: .zero, registry: sketchTestRegistry)
        let editor = makeEditor([sketch], registry: sketchTestRegistry)
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.pointerDragged(from: point, to: point, clickCount: 2)
        editor.pointerCancelled()
        #expect(editor.inspectorRequest == nil, "the cancelled second press opened nothing")
        #expect(editor.lastClick == nil)
        editor.click(point, clickCount: 2)
        #expect(editor.inspectorRequest == nil, "and the first click was forgotten with it")
    }

    @Test func aCancelledPressSelectsNothing() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: point, to: point)
        editor.pointerCancelled()
        #expect(editor.selection == [a.id])
    }

    @Test func aCancelWithNoPressChangesNothingAndTheNextPressIsFresh() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.pointerCancelled()
        #expect(editor.selection == [a.id] && editor.interaction == nil)
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start + Vector2(10, 0), modifiers: .shift)
        editor.pointerCancelled()
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id], "nothing of the cancelled press, its ⇧ included, leaks into the next")
    }

    @Test func aCancelledMiddlePanEndsWhereItWasAndTheNextOneIsFresh() {
        let editor = makeEditor([])
        editor.middleDragged(from: Vector2(100, 100), to: Vector2(100, 100))
        editor.middleDragged(from: Vector2(100, 100), to: Vector2(140, 120))
        let panned = editor.transform
        #expect(editor.canvasCursor == .grabbing)
        editor.middleCancelled()
        #expect(editor.interaction == nil && editor.canvasCursor == nil && editor.transform == panned)
        editor.middleDrag(Vector2(300, 300), Vector2(310, 300))
        #expect(editor.transform.offset == panned.offset + Vector2(10, 0), "the next pan measures from its own press")
        editor.middleCancelled()
        #expect(editor.transform.offset == panned.offset + Vector2(10, 0), "a cancel with no pan changes nothing")
    }

    @Test func aCancelledLibraryDragRemovesTheGhostAndAddsNothing() throws {
        let editor = makeEditor([], dock: .bottom)
        editor.panelPlacement = PanelPlacement(window: Vector2(1000, 700),
                                               panel: CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300)))
        let canvas = try #require(editor.canvasFrameInWindow)
        let start = Vector2(canvas.origin.x + 40, canvas.origin.y - 100)
        editor.moveLibraryDrag(FilletTestNode.typeID, from: start, to: canvas.origin + Vector2(120, 60))
        #expect(editor.libraryDrag != nil)
        editor.cancelLibraryDrag()
        #expect(editor.libraryDrag == nil && editor.graph.nodes.isEmpty)
        editor.cancelLibraryDrag()
        #expect(editor.libraryDrag == nil)
    }
}
