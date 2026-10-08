import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct PointerTests {
    @Test func clickSelectsAndShiftClickToggles() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [a.id])
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        editor.modifiers = .shift
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [b.id])
    }

    @Test func clickOnEmptyCanvasClearsUnlessShiftIsHeld() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.modifiers = .shift
        editor.click(Vector2(600, 600))
        #expect(editor.selection == [a.id])
        editor.modifiers = []
        editor.click(Vector2(600, 600))
        #expect(editor.selection.isEmpty)
    }

    @Test func aTinyMoveIsStillAClick() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(2, 1))
        #expect(editor.selection == [a.id])
        #expect(editor.graph.nodes[a.id]?.position == .zero)
        #expect(!editor.document.canUndo)
    }

    @Test func anOptionClickDoesNotDuplicate() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        editor.modifiers = .option
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(2, 1))
        #expect(editor.graph.nodes.count == 1)
        #expect(editor.selection == [a.id])
        #expect(!editor.document.canUndo)
    }

    @Test func aPressThatNeverEndedDoesNotLeakIntoTheNext() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(50, 0))
        // No release: the window lost the gesture. The next press starts afresh.
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        #expect(editor.graph.nodes[a.id]?.position == Vector2(50, 0))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 0))
        #expect(editor.interaction == nil)
    }

    @Test func plainDragOnEmptyCanvasPans() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        editor.drag(Vector2(100, 100), Vector2(130, 80))
        #expect(editor.transform == CanvasTransform(offset: Vector2(35, -15), zoom: 2))
        #expect(editor.document.viewState.canvasOffset == Vector2(35, -15))
        #expect(editor.interaction == nil)
    }

    @Test func shiftDragOnEmptyCanvasBoxSelectsAddingToTheSelection() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))
        let c = testNode(NumberTestNode.self, id: 3, at: Vector2(800, 0))
        let editor = makeEditor([a, b, c])
        editor.selection = [c.id]
        editor.modifiers = .shift
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(420, 20))
        guard case .boxSelecting(let corner, let current, let base)? = editor.interaction else {
            Issue.record("expected a box selection"); return
        }
        #expect(corner == start && current == Vector2(420, 20) && base == [c.id])
        editor.pointerReleased(from: start, at: Vector2(420, 20))
        #expect(editor.selection == [b.id, c.id])
        #expect(editor.transform.offset == .zero)
    }

    @Test func draggingANodeMovesTheSelectionInOneUndoStep() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.transform = CanvasTransform(zoom: 2)
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(10, 10))
        editor.pointerDragged(from: start, to: start + Vector2(40, 20))
        editor.pointerReleased(from: start, at: start + Vector2(40, 20))
        // 40×20 screen points at zoom 2 is 20×10 canvas points.
        #expect(editor.graph.nodes[a.id]?.position == Vector2(20, 10))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(320, 10))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero)
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 0))
        #expect(!editor.document.canUndo)
    }

    @Test func draggingAnUnselectedNodeSelectsItFirst() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.selection = [b.id]
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(0, 50))
        #expect(editor.selection == [a.id])
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 50))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 0))
    }

    @Test func leftDockMovesInStoredCoordinates() {
        let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 0))
        let editor = makeEditor([a], dock: .left)
        let start = editor.screenPoint(in: a.id)
        // Down the screen in the vertical flow is along the stored x axis.
        editor.drag(start, start + Vector2(0, 30))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(130, 0))
    }

    @Test func optionDragDuplicatesAsOneUndoStepAndLeavesTheOriginals() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.selection = [rect.id, extrude.id]
        editor.modifiers = .option
        let start = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 200))
        guard case .duplicating(_, let delta)? = editor.interaction else { Issue.record("expected ghosts"); return }
        #expect(delta == Vector2(0, 200))
        #expect(editor.graph.nodes.count == 2)
        editor.pointerReleased(from: start, at: start + Vector2(0, 200))
        #expect(editor.graph.nodes.count == 4)
        #expect(editor.graph.links.count == 2)
        #expect(editor.graph.nodes[rect.id]?.position == .zero)
        let copies = editor.selection.compactMap { editor.graph.nodes[$0] }
        #expect(Set(copies.map(\.position)) == [Vector2(0, 200), Vector2(300, 200)])
        editor.document.undo()
        #expect(editor.graph.nodes.count == 2)
        #expect(!editor.document.canUndo)
    }
}
