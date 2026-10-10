import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Dragging comments (canvas comments spec 2026-10-09 §7, §3): any selected item moves every selected node and
/// comment together; a frame dragged by its title bar carries the nodes it holds; each drag is one undo step.
@MainActor
struct CommentMoveTests {
    let inside = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))
    let outside = testNode(NumberTestNode.self, id: 2, at: Vector2(700, 100))
    let sticky = note(1, at: Vector2(450, 0))
    let frame = box(2, at: Vector2(50, 50), size: Vector2(400, 300))

    func editor(dock: DockSide = .bottom) -> EditorModel {
        makeEditor([inside, outside], stickies: [sticky], frames: [frame], dock: dock)
    }

    func titleBar(_ editor: EditorModel) -> Vector2 { editor.screenPoint(inComment: frame.id, inset: Vector2(200, 10)) }

    @Test func draggingAFrameByItsTitleBarMovesItAndItsNodesAsOneStep() {
        let editor = editor()
        let start = titleBar(editor)
        editor.drag(start, start + Vector2(30, 40))
        #expect(editor.graph.frames[frame.id]?.frame.origin == Vector2(80, 90))
        #expect(editor.graph.nodes[inside.id]?.position == Vector2(130, 140))
        #expect(editor.graph.nodes[outside.id]?.position == Vector2(700, 100), "not a member")
        #expect(editor.canvasSelection == CanvasSelection(comments: [frame.id]))
        editor.document.undo()
        #expect(editor.graph.frames[frame.id] == frame && editor.graph.nodes[inside.id]?.position == Vector2(100, 100))
        #expect(!editor.document.canUndo, "a drag of several steps is one undo step")
    }

    @Test func aFrameMovesItsMembersAsTheyWereWhenTheDragBegan() {
        let editor = editor()
        let start = titleBar(editor)
        editor.pointerDragged(from: start, to: start, modifiers: [])
        editor.pointerDragged(from: start, to: start + Vector2(500, 0), modifiers: [])
        // The frame now covers `outside` (stored 700, 100), but only the nodes it held at the start travel.
        editor.pointerDragged(from: start, to: start + Vector2(520, 10), modifiers: [])
        editor.pointerReleased(from: start, at: start + Vector2(520, 10), modifiers: [])
        #expect(editor.graph.nodes[outside.id]?.position == Vector2(700, 100))
        #expect(editor.graph.nodes[inside.id]?.position == Vector2(620, 110))
    }

    @Test func aMixedDragMovesNodesAndCommentsTogetherAsOneStep() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [outside.id], comments: [sticky.id])
        let start = editor.screenPoint(inComment: sticky.id, inset: Vector2(20, 20))
        editor.drag(start, start + Vector2(-10, 25))
        #expect(editor.graph.stickies[sticky.id]?.frame.origin == Vector2(440, 25))
        #expect(editor.graph.nodes[outside.id]?.position == Vector2(690, 125))
        #expect(editor.graph.nodes[inside.id]?.position == Vector2(100, 100))
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id] == sticky && editor.graph.nodes[outside.id]?.position == Vector2(700, 100))
        #expect(!editor.document.canUndo)
    }

    @Test func draggingAnUnselectedNoteSelectsItFirst() {
        let editor = editor()
        editor.selection = [outside.id]
        let start = editor.screenPoint(inComment: sticky.id, inset: Vector2(20, 20))
        editor.drag(start, start + Vector2(10, 0))
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]), "a plain press replaces the selection")
        #expect(editor.graph.nodes[outside.id]?.position == Vector2(700, 100))
        editor.selection = [outside.id]
        editor.drag(start, start + Vector2(10, 0), modifiers: .shift)
        #expect(editor.canvasSelection == CanvasSelection(nodes: [outside.id], comments: [sticky.id]), "⇧ adds, then moves both")
    }

    @Test func aDragInTheLeftDockMovesCommentsInStoredCoordinates() {
        let editor = editor(dock: .left)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        let start = editor.screenPoint(inComment: sticky.id, inset: Vector2(20, 20))
        editor.drag(start, start + Vector2(7, 3))  // display (7, 3) is stored (3, 7)
        #expect(editor.graph.stickies[sticky.id]?.frame.origin == Vector2(453, 7))
    }

    @Test func aBoxSelectsCommentsAndNodesAndTheArrowsNudgeThemTogether() {
        let editor = editor()
        editor.drag(Vector2(470, 330), Vector2(900, -50))  // over the note and `outside`, not the frame or `inside`
        #expect(editor.canvasSelection == CanvasSelection(nodes: [outside.id], comments: [sticky.id]))
        #expect(editor.perform(.nudge(Vector2(10, 0), isRepeat: false)))
        #expect(editor.graph.stickies[sticky.id]?.frame.origin == Vector2(460, 0))
        #expect(editor.graph.nodes[outside.id]?.position == Vector2(710, 100))
    }

    @Test func nudgingAFrameCarriesItsNodes() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [frame.id])
        editor.perform(.nudge(Vector2(0, 10), isRepeat: false))
        #expect(editor.graph.frames[frame.id]?.frame.origin == Vector2(50, 60))
        #expect(editor.graph.nodes[inside.id]?.position == Vector2(100, 110))
        #expect(editor.graph.nodes[outside.id]?.position == Vector2(700, 100))
    }

    @Test func aMemberAlsoSelectedMovesOnlyOnce() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [inside.id], comments: [frame.id])
        let start = titleBar(editor)
        editor.drag(start, start + Vector2(10, 0))
        #expect(editor.graph.nodes[inside.id]?.position == Vector2(110, 100))
    }

    @Test func anOptionDragCopiesTheCommentsOnReleaseWithoutCarryingTheNodes() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [frame.id, sticky.id])
        let start = titleBar(editor)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        #expect(editor.graph.frames.count == 1, "nothing copied before the pointer moves")
        editor.pointerDragged(from: start, to: start + Vector2(0, 400), modifiers: .option)
        editor.pointerReleased(from: start, at: start + Vector2(0, 400), modifiers: .option)
        #expect(editor.graph.frames.count == 2 && editor.graph.stickies.count == 2 && editor.graph.nodes.count == 2)
        #expect(editor.graph.frames[frame.id] == frame, "the original stayed")
        let copies = editor.canvasSelection
        #expect(copies.comments.count == 2 && copies.comments.isDisjoint(with: [frame.id, sticky.id]))
        let copiedFrame = copies.comments.compactMap { editor.graph.frames[$0] }.first
        #expect(copiedFrame?.frame.origin == Vector2(50, 450))
    }

    @Test func escWhileBoxSelectingOverCommentsPutsBackTheSelection() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [frame.id])
        editor.pointerDragged(from: Vector2(470, 330), to: Vector2(470, 330))
        editor.pointerDragged(from: Vector2(470, 330), to: Vector2(900, -50))
        #expect(editor.canvasSelection.comments == [sticky.id])
        #expect(editor.perform(.cancel))
        #expect(editor.canvasSelection == CanvasSelection(comments: [frame.id]))
    }
}
