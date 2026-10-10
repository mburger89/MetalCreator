import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// Resizing from the bottom-right handle of a selected comment (canvas comments spec 2026-10-09 §7): top-left fixed,
/// at least 80 × 40, one undo step; nodes never move.
@MainActor
struct CommentResizeTests {
    let node = testNode(NumberTestNode.self, id: 1, at: Vector2(60, 70))
    let sticky = note(1, at: Vector2(300, 50))
    let frame = box(2, at: Vector2(50, 50), size: Vector2(200, 150))

    func editor(dock: DockSide = .bottom) -> EditorModel {
        let editor = makeEditor([node], stickies: [sticky], frames: [frame], dock: dock)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id, frame.id])
        return editor
    }

    /// The middle of a comment's handle, in screen points.
    func handle(_ editor: EditorModel, _ id: CommentID) -> Vector2 {
        let rect = editor.frame(ofComment: id) ?? CanvasRect(origin: .zero, size: .zero)
        return editor.transform.toScreen(CommentLayout.handle(of: rect).centre)
    }

    @Test func draggingTheHandleResizesWithTheTopLeftFixedAsOneUndoStep() {
        let editor = editor()
        let start = handle(editor, sticky.id)
        editor.drag(start, start + Vector2(40, 25))
        #expect(editor.graph.stickies[sticky.id]?.frame == CanvasRect(origin: Vector2(300, 50), size: Vector2(200, 125)))
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id, frame.id]), "a resize keeps the selection")
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id] == sticky)
        #expect(!editor.document.canUndo, "every step of the drag was one undo step")
    }

    @Test func aFrameResizesToo() {
        let editor = editor()
        let start = handle(editor, frame.id)
        editor.drag(start, start + Vector2(-20, 30))
        #expect(editor.graph.frames[frame.id]?.frame == CanvasRect(origin: Vector2(50, 50), size: Vector2(180, 180)))
    }

    @Test func theSizeNeverFallsBelowEightyByForty() {
        let editor = editor()
        let start = handle(editor, sticky.id)
        editor.drag(start, start + Vector2(-500, -500))
        #expect(editor.graph.stickies[sticky.id]?.frame == CanvasRect(origin: Vector2(300, 50), size: Vector2(80, 40)))
        let wide = self.editor()
        let from = handle(wide, sticky.id)
        wide.drag(from, from + Vector2(-500, 60))
        #expect(wide.graph.stickies[sticky.id]?.frame.size == Vector2(80, 160), "each axis clamps on its own")
    }

    @Test func aResizeDoesNotMoveTheNodesAFrameHolds() {
        let editor = editor()
        let start = handle(editor, frame.id)
        editor.drag(start, start + Vector2(-100, -100))
        #expect(editor.graph.nodes[node.id]?.position == Vector2(60, 70))
    }

    @Test func theDeltaIsInCanvasPointsAtAnyZoom() {
        let editor = editor()
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        let start = handle(editor, sticky.id)
        editor.drag(start, start + Vector2(40, 20))  // 20 × 10 canvas points
        #expect(editor.graph.stickies[sticky.id]?.frame.size == Vector2(180, 110))
    }

    @Test func theLeftDockResizesAsDrawnAndStoresTheTranspose() {
        let editor = editor(dock: .left)
        let start = handle(editor, sticky.id)
        editor.drag(start, start + Vector2(30, 10))  // drawn 100 × 160 grows to 130 × 170; stored 170 × 130
        #expect(editor.graph.stickies[sticky.id]?.frame == CanvasRect(origin: Vector2(300, 50), size: Vector2(170, 130)))
        editor.drag(handle(editor, sticky.id), handle(editor, sticky.id) + Vector2(-400, -400))
        #expect(editor.graph.stickies[sticky.id]?.frame.size == Vector2(40, 80), "drawn 80 × 40, stored transposed")
    }

    @Test func onlyASelectedCommentsHandleResizes() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [frame.id])
        let start = handle(editor, sticky.id)
        editor.drag(start, start + Vector2(40, 25))
        #expect(editor.graph.stickies[sticky.id]?.frame.size == Vector2(160, 100), "the unselected note moved instead")
        #expect(editor.graph.stickies[sticky.id]?.frame.origin == Vector2(340, 75))
    }

    @Test func aClickOnTheHandleChangesNothing() {
        let editor = editor()
        editor.click(handle(editor, sticky.id))
        #expect(editor.graph.stickies[sticky.id] == sticky && !editor.document.canUndo)
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]), "a plain click collapses to it")
    }

    @Test func escDuringAResizeIsClaimedAndKeepsTheSelection() {
        let editor = editor()
        let start = handle(editor, sticky.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(20, 20))
        #expect(editor.perform(.cancel))
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id, frame.id]))
        editor.pointerReleased(from: start, at: start + Vector2(20, 20))
        #expect(editor.graph.stickies[sticky.id]?.frame.size == Vector2(180, 120), "the steps already made stay, for Undo")
    }

    @Test func aResizeEndsItsCoalescingSoTheNextEditIsItsOwnStep() throws {
        let editor = editor()
        let start = handle(editor, sticky.id)
        editor.drag(start, start + Vector2(10, 10))
        var renamed = try #require(editor.graph.stickies[sticky.id])
        renamed.text = "Changed"
        try editor.document.perform(.setSticky(renamed))
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.frame.size == Vector2(170, 110) && editor.document.canUndo)
    }
}
