import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// What a press on the canvas hits with comments there (canvas comments spec 2026-10-09 §7): a note on its whole
/// rectangle; a frame only on its title bar and a 6 pt inner edge band; notes beat frames, nodes beat both; the
/// selected raise within their kind and a selected comment's bottom-right handle resizes it.
@MainActor
struct CommentHitTests {
    let frame = box(1, at: Vector2(100, 100), size: Vector2(400, 300))
    let sticky = note(1, at: Vector2(120, 130))

    @Test func aNoteHitsOnItsWholeRectangle() {
        let editor = makeEditor([], stickies: [sticky])
        #expect(editor.hitTest(Vector2(121, 131)) == .note(sticky.id))
        #expect(editor.hitTest(Vector2(279, 229)) == .note(sticky.id))
        #expect(editor.hitTest(Vector2(119, 131)) == .empty)
        #expect(editor.hitTest(Vector2(200, 232)) == .empty)
    }

    @Test func aFrameHitsOnlyOnItsTitleBarAndEdgeBand() {
        let editor = makeEditor([], frames: [frame])
        #expect(editor.hitTest(Vector2(300, 110)) == .frame(frame.id), "title bar")
        #expect(editor.hitTest(Vector2(103, 300)) == .frame(frame.id), "left band")
        #expect(editor.hitTest(Vector2(300, 397)) == .frame(frame.id), "bottom band")
        #expect(editor.hitTest(Vector2(300, 300)) == .empty, "inside: the canvas shows through, so a box starts there")
    }

    @Test func aNodeInsideAFrameStillHits() {
        let node = testNode(NumberTestNode.self, id: 1, at: Vector2(200, 200))
        let editor = makeEditor([node], frames: [frame])
        #expect(editor.hitTest(editor.screenPoint(in: node.id)) == .node(node.id))
    }

    @Test func aNoteBeatsAFrameAndANodeBeatsANote() {
        let over = note(2, at: Vector2(250, 95), size: Vector2(100, 100))  // covers the frame's title bar
        let node = testNode(NumberTestNode.self, id: 1, at: Vector2(260, 100))
        let editor = makeEditor([], stickies: [over], frames: [frame])
        #expect(editor.hitTest(Vector2(300, 110)) == .note(over.id))
        #expect(editor.hitTest(Vector2(200, 110)) == .frame(frame.id), "the title bar beside the note")
        let withNode = makeEditor([node], stickies: [over], frames: [frame])
        #expect(withNode.hitTest(Vector2(300, 110)) == .node(node.id))
    }

    @Test func theSelectedRaiseWithinTheirKind() {
        let back = note(1, at: .zero), front = note(2, at: Vector2(20, 20))
        let editor = makeEditor([], stickies: [back, front])
        #expect(editor.hitTest(Vector2(50, 50)) == .note(front.id))
        editor.canvasSelection = CanvasSelection(comments: [back.id])
        #expect(editor.hitTest(Vector2(50, 50)) == .note(back.id), "a selected note draws last, so it is hit first")
        let twoFrames = makeEditor([], frames: [box(1, at: .zero), box(2, at: Vector2(10, 10))])
        #expect(twoFrames.hitTest(Vector2(50, 12)) == .frame(commentID(2)))
        twoFrames.canvasSelection = CanvasSelection(comments: [commentID(1)])
        #expect(twoFrames.hitTest(Vector2(50, 12)) == .frame(commentID(1)))
    }

    @Test func aSelectedCommentsBottomRightHandleResizesAndAnUnselectedOneDoesNot() {
        let editor = makeEditor([], stickies: [sticky], frames: [frame])
        let noteCorner = Vector2(275, 225), frameCorner = Vector2(495, 395)
        #expect(editor.hitTest(noteCorner) == .note(sticky.id))
        #expect(editor.hitTest(frameCorner) == .frame(frame.id))
        editor.canvasSelection = CanvasSelection(comments: [sticky.id, frame.id])
        #expect(editor.hitTest(noteCorner) == .resize(sticky.id))
        #expect(editor.hitTest(frameCorner) == .resize(frame.id))
        #expect(editor.hitTest(Vector2(260, 215)) == .note(sticky.id), "outside the 12 point handle")
    }

    @Test func hitsReadTheCanvasTransformAndTheLeftDocksFlow() {
        let editor = makeEditor([], stickies: [sticky], dock: .left)
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        // Stored (120, 130) is drawn at (130, 120), 100 × 160.
        #expect(editor.hitTest(editor.transform.toScreen(Vector2(131, 121))) == .note(sticky.id))
        #expect(editor.hitTest(editor.transform.toScreen(Vector2(125, 121))) == .empty)
    }

    @Test func aHitSelectsItsComment() {
        let editor = makeEditor([], stickies: [sticky], frames: [frame])
        #expect(editor.items(for: .note(sticky.id)) == CanvasSelection(comments: [sticky.id]))
        #expect(editor.items(for: .frame(frame.id)) == CanvasSelection(comments: [frame.id]))
        #expect(editor.items(for: .resize(frame.id)) == CanvasSelection(comments: [frame.id]))
    }
}
