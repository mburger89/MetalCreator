import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// Comments are items of the one canvas selection (canvas comments spec 2026-10-09 §7, §3; multi-select Errata (A)).
@MainActor
struct CommentSelectionTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(600, 0))
    let sticky = note(1, at: Vector2(300, 0))
    let frame = box(2, at: Vector2(0, 400), size: Vector2(400, 300))

    func editor(dock: DockSide = .bottom) -> EditorModel {
        makeEditor([a, b], stickies: [sticky], frames: [frame], dock: dock)
    }

    @Test func theModesReplaceAddAndToggleCommentsToo() {
        let one = CanvasSelection(nodes: [a.id], comments: [commentID(1)])
        let two = CanvasSelection(nodes: [b.id], comments: [commentID(1), commentID(2)])
        #expect(one.applying(two, mode: .replace) == two)
        #expect(one.applying(two, mode: .add) == CanvasSelection(nodes: [a.id, b.id], comments: [commentID(1), commentID(2)]))
        #expect(one.applying(two, mode: .toggle) == CanvasSelection(nodes: [a.id, b.id], comments: [commentID(2)]))
        #expect(one.isSuperset(of: CanvasSelection(comments: [commentID(1)])) && !one.isSuperset(of: two))
        #expect(!CanvasSelection(comments: [commentID(1)]).isEmpty && CanvasSelection().isEmpty)
    }

    @Test func assigningTheNodeSelectionClearsSelectedComments() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [a.id], comments: [sticky.id, frame.id])
        editor.selection = [b.id]
        #expect(editor.canvasSelection == CanvasSelection(nodes: [b.id]))
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        editor.selection = []
        #expect(editor.canvasSelection.isEmpty, "even an empty assignment drops the comments")
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.selection.isEmpty, "the node view of a comment-only selection is empty")
    }

    @Test func selectAllTakesEveryNodeAndComment() {
        let editor = editor()
        editor.selectAll()
        #expect(editor.canvasSelection == CanvasSelection(nodes: [a.id, b.id], comments: [sticky.id, frame.id]))
        #expect(editor.allItems == editor.canvasSelection)
    }

    @Test func aBoxSelectsNotesByTheirRectangleAndFramesByTheirChrome() {
        let editor = editor()
        let overNote = CanvasRect(corner: Vector2(310, 10), Vector2(320, 20))
        #expect(editor.items(intersecting: overNote) == CanvasSelection(comments: [sticky.id]))
        let inFrameInterior = CanvasRect(corner: Vector2(100, 500), Vector2(200, 600))
        #expect(editor.items(intersecting: inFrameInterior).isEmpty, "a box among the nodes inside a frame doesn't take the frame")
        let acrossTitleBar = CanvasRect(corner: Vector2(100, 380), Vector2(200, 420))
        #expect(editor.items(intersecting: acrossTitleBar) == CanvasSelection(comments: [frame.id]))
        let crossingTheEdge = CanvasRect(corner: Vector2(100, 500), Vector2(450, 600))
        #expect(editor.items(intersecting: crossingTheEdge) == CanvasSelection(comments: [frame.id]))
        let everything = CanvasRect(corner: Vector2(-10, -10), Vector2(900, 800))
        #expect(editor.items(intersecting: everything) == editor.allItems)
    }

    @Test func positionsOfCommentsAreTheirFrameOrigins() {
        let editor = editor()
        let items = CanvasSelection(nodes: [a.id], comments: [sticky.id, frame.id, commentID(9)])
        let start = editor.positions(of: items)
        #expect(start == SelectionPositions(nodes: [a.id: .zero], comments: [sticky.id: Vector2(300, 0), frame.id: Vector2(0, 400)]))
        #expect(start.items == CanvasSelection(nodes: [a.id], comments: [sticky.id, frame.id]), "the gone comment is skipped")
        #expect(editor.positions(of: CanvasSelection(comments: [commentID(9)])).isEmpty)
    }

    @Test func movingCommentsReplacesThemWholeAtTheOffsetPositionInStoredCoordinates() {
        let editor = editor()
        let start = editor.positions(of: editor.allItems)
        var movedNote = sticky, movedFrame = frame
        movedNote.frame.origin = Vector2(305, 7)
        movedFrame.frame.origin = Vector2(5, 407)
        #expect(editor.moveCommands(from: start, by: Vector2(5, 7))
            == [.move(a.id, to: Vector2(5, 7)), .move(b.id, to: Vector2(605, 7)), .setSticky(movedNote), .setFrame(movedFrame)])
        var stale = start
        stale.comments[commentID(9)] = .zero
        #expect(editor.moveCommands(from: stale, by: .zero).count == 4, "a comment that is gone is skipped")
    }

    @Test func boundsCoverNodesAndCommentsInDisplayPoints() {
        let editor = editor()
        let size = NodeLayout.size(editor.shape(of: b))
        #expect(editor.bounds(of: editor.allItems)
            == CanvasRect(origin: .zero, size: Vector2(600 + size.x, 700)))
        #expect(editor.bounds(of: CanvasSelection(comments: [sticky.id])) == editor.frame(of: sticky))
        #expect(editor.bounds(of: CanvasSelection(comments: [commentID(9)])) == nil)
        let left = self.editor(dock: .left)
        #expect(left.bounds(of: CanvasSelection(comments: [frame.id])) == CanvasRect(origin: Vector2(400, 0), size: Vector2(300, 400)))
    }

    @Test func aClickOnACommentSelectsItAndAShiftClickAddsIt() {
        let editor = editor()
        editor.selection = [a.id]
        editor.click(editor.screenPoint(inComment: sticky.id, inset: Vector2(5, 5)))
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        editor.click(editor.screenPoint(inComment: frame.id, inset: Vector2(5, 5)), modifiers: .shift)
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id, frame.id]))
        editor.click(editor.screenPoint(inComment: sticky.id, inset: Vector2(5, 5)), modifiers: .command)
        #expect(editor.canvasSelection == CanvasSelection(comments: [frame.id]))
    }
}
