import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// What a press on a wire or a tie hits (cable ties spec 2026-10-26 §4.1): a wire within 5 points of its taut route, a tie
/// anywhere on its band; priority socket, tie, node, note, wire, frame, empty, with a selected comment's handle just before
/// its own comment (plan ruling R3).
@MainActor
struct WireHitTests {
    let scene = TieScene()

    @Test func aPointOnOrNearAWireHitsIt() {
        let editor = scene.editor()
        #expect(editor.hitTest(scene.upperMiddle) == .wire(scene.upper))
        #expect(editor.hitTest(scene.upperMiddle + Vector2(0, 4)) == .wire(scene.upper))
        #expect(editor.hitTest(scene.upperMiddle + Vector2(0, 7)) == .empty)
        #expect(editor.hitTest(scene.lowerMiddle) == .wire(scene.lower))
    }

    @Test func theDistanceIsInCanvasPointsUnderZoomAndPan() {
        let editor = scene.editor()
        editor.transform = CanvasTransform(offset: Vector2(-40, 30), zoom: 2)
        let point = editor.transform.toScreen(scene.upperMiddle + Vector2(0, 4))
        #expect(editor.hitTest(point) == .wire(scene.upper))
        #expect(editor.hitTest(editor.transform.toScreen(scene.upperMiddle + Vector2(0, 7))) == .empty)
    }

    @Test func aTiedWireHitsAlongItsTautRoute() throws {
        let editor = scene.editor(ties: [scene.tie()])
        let onRoute = try #require(editor.wireRouting.routes[scene.upper]?.pieces.first?.point(at: 0.5))
        #expect(editor.hitTest(onRoute) == .wire(scene.upper))
        #expect(editor.hitTest(scene.upperMiddle) == .empty, "the straight line it used to be is empty now")
    }

    @Test func aTieHitsAnywhereOnItsBand() {
        let editor = scene.editor(ties: [scene.tie()])
        #expect(editor.hitTest(Vector2(384, 160)) == .tie(tieID(1)))
        #expect(editor.hitTest(Vector2(381.5, 155.5)) == .tie(tieID(1)), "the band's corner")
        #expect(editor.hitTest(Vector2(384, 158)) == .tie(tieID(1)), "a lane is the tie's, not its wire's")
    }

    @Test func aSocketBeatsATieAndATieBeatsANode() {
        let onSocket = scene.editor(ties: [scene.tie(at: Vector2(600, 60))])
        #expect(onSocket.hitTest(Vector2(600, 60)) == .socket(SocketRef(scene.upper, isInput: true)))
        let onNode = scene.editor(ties: [scene.tie(at: Vector2(84, 30))])
        #expect(onNode.hitTest(Vector2(84, 30)) == .tie(tieID(1)), "a tie dropped on a node can still be grabbed")
        #expect(onNode.hitTest(Vector2(20, 40)) == .node(scene.a1.id), "the rest of the node is the node's")
    }

    @Test func aNoteBeatsAWireAndAWireBeatsAFrame() {
        let covered = scene.editor(stickies: [note(1, at: Vector2(334, 10), size: Vector2(100, 100))])
        #expect(covered.hitTest(scene.upperMiddle) == .note(commentID(1)))
        let frame = box(2, at: Vector2(300, 40), size: Vector2(200, 200))
        #expect(makeEditor(scene.nodes, [], frames: [frame]).hitTest(scene.upperMiddle) == .frame(frame.id),
                "set up: without the wire the point is the frame's title bar")
        #expect(scene.editor(frames: [frame]).hitTest(scene.upperMiddle) == .wire(scene.upper))
    }

    @Test func theLeftDockHitsTheTransposedRoute() throws {
        let editor = scene.editor(dock: .left)
        let onUpper = try #require(editor.wireRouting.routes[scene.upper]?.pieces.first?.point(at: 0.5))
        #expect(onUpper == Vector2(94, 338), "set up: the vertical flow's route")
        #expect(editor.hitTest(onUpper) == .wire(scene.upper))
    }

    /// Wires cross the canvas everywhere, so a drag that starts on one draws a box (plan ruling R5).
    @Test func aDragThatStartsOnAWireDrawsABox() {
        let editor = scene.editor()
        editor.drag(scene.upperMiddle, Vector2(900, 300))
        #expect(editor.selection == [scene.b1.id, scene.b2.id], "the box covered the two nodes on the right")
        #expect(editor.canvasSelection.wires.isEmpty && !editor.document.canUndo)
    }
}
