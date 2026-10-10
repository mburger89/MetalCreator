import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// Where comments are drawn and what a frame holds (canvas comments spec 2026-10-09 §7).
@MainActor
struct CommentGeometryTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))

    @Test func aCommentIsDrawnWhereItIsStoredInTheBottomDockAndTransposedInTheLeftOne() {
        let n = note(1, at: Vector2(10, 20), size: Vector2(160, 100))
        #expect(makeEditor([], stickies: [n]).frame(of: n) == CanvasRect(origin: Vector2(10, 20), size: Vector2(160, 100)))
        let left = makeEditor([], stickies: [n], dock: .left)
        #expect(left.frame(of: n) == CanvasRect(origin: Vector2(20, 10), size: Vector2(100, 160)), "origin and size swap")
        #expect(left.frame(ofComment: n.id) == left.frame(of: n))
        #expect(left.frame(ofComment: commentID(9)) == nil)
    }

    @Test func aFrameHoldsTheNodesWhoseCentresAreInsideIt() {
        let size = NodeLayout.size(NodeShape(a, in: makeEditor([a]).graph, registry: editorTestRegistry))
        let centre = Vector2(100, 100) + size * 0.5
        let inside = box(1, at: centre - Vector2(10, 10), size: Vector2(20, 20))
        let editor = makeEditor([a], frames: [inside])
        #expect(editor.members(of: inside) == [a.id])
        // The node overlaps the frame but its centre is outside: not a member.
        let beside = box(2, at: Vector2(centre.x + 1, centre.y - 10), size: Vector2(300, 20))
        #expect(makeEditor([a], frames: [beside]).members(of: beside).isEmpty)
        // A centre exactly on the edge is inside.
        let onEdge = box(3, at: centre, size: Vector2(50, 50))
        #expect(makeEditor([a], frames: [onEdge]).members(of: onEdge) == [a.id])
    }

    @Test func membershipFollowsTheNodesAcrossTheFrameEdge() {
        let frame = box(1, at: .zero, size: Vector2(400, 300))
        let editor = makeEditor([a], frames: [frame])
        #expect(editor.members(of: frame) == [a.id])
        try? editor.document.perform(.move(a.id, to: Vector2(900, 900)))
        #expect(editor.members(of: frame).isEmpty, "nothing about membership is stored")
        try? editor.document.perform(.move(a.id, to: Vector2(100, 100)))
        #expect(editor.members(of: frame) == [a.id])
    }

    @Test func membershipIsReadInDisplayPointsInTheLeftDock() {
        // Stored (100, 100) is drawn at (100, 100) too, but a node at stored (600, 0) is drawn at (0, 600).
        let far = testNode(NumberTestNode.self, id: 2, at: Vector2(600, 0))
        let frame = box(1, at: Vector2(550, 0), size: Vector2(300, 200))  // stored; drawn at (0, 550), 200 × 300
        let editor = makeEditor([far], frames: [frame], dock: .left)
        #expect(editor.members(of: frame) == [far.id])
    }

    @Test func theChromeIsTheTitleBarAndAnEdgeBandOnly() {
        let rect = CanvasRect(origin: Vector2(100, 100), size: Vector2(400, 300))
        func chrome(_ x: Double, _ y: Double) -> Bool { CommentLayout.chromeContains(rect, Vector2(x, y)) }
        #expect(chrome(300, 110), "the title bar")
        #expect(chrome(300, 121.9) && !chrome(300, 128.1), "the title bar is 22 points, the band 6 below it")
        #expect(chrome(103, 300) && chrome(497, 300) && chrome(300, 397), "the left, right and bottom bands")
        #expect(!chrome(107, 300) && !chrome(493, 300) && !chrome(300, 393), "just inside the bands")
        #expect(!chrome(300, 300), "the interior")
        #expect(!chrome(99, 110) && !chrome(300, 401), "outside")
        #expect(CommentLayout.chromeContains(CanvasRect(origin: .zero, size: Vector2(10, 10)), Vector2(5, 5)), "a tiny frame is all chrome")
    }

    @Test func framingPadsTheBoundsAndAddsTheTitleBar() {
        let bounds = CanvasRect(origin: Vector2(100, 100), size: Vector2(200, 80))
        #expect(CommentLayout.framing(bounds) == CanvasRect(origin: Vector2(76, 54), size: Vector2(248, 150)))
    }

    @Test func theHandleIsTheBottomRightCorner() {
        let rect = CanvasRect(origin: Vector2(10, 20), size: Vector2(160, 100))
        #expect(CommentLayout.handle(of: rect) == CanvasRect(origin: Vector2(158, 108), size: Vector2(12, 12)))
        #expect(CommentLayout.clamped(Vector2(10, 100)) == Vector2(80, 100))
        #expect(CommentLayout.clamped(Vector2(200, 5)) == Vector2(200, 40))
    }

    @Test func notesAndFramesDrawByIDWithTheSelectedLast() {
        let editor = makeEditor([], stickies: [note(3), note(1), note(2)], frames: [box(5), box(4)])
        #expect(editor.drawOrderNotes.map(\.id) == [commentID(1), commentID(2), commentID(3)])
        #expect(editor.drawOrderFrames.map(\.id) == [commentID(4), commentID(5)])
        editor.canvasSelection = CanvasSelection(comments: [commentID(1), commentID(4)])
        #expect(editor.drawOrderNotes.map(\.id) == [commentID(2), commentID(3), commentID(1)])
        #expect(editor.drawOrderFrames.map(\.id) == [commentID(5), commentID(4)])
    }
}
