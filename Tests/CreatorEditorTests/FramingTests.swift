import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// F frames the selection in the graph canvas when the pointer is over it (spec 2026-10-09 §3): its bounds fill the
/// visible canvas inside 40 points of padding, centred, the zoom within range; with nothing selected, everything.
@MainActor
struct FramingTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(1000, 0))

    func close(_ p: Vector2, _ q: Vector2) -> Bool { (p - q).length < 1e-9 }

    @Test func framingCentresARectAndFitsItInsideThePadding() {
        let rect = CanvasRect(origin: Vector2(0, 0), size: Vector2(1440, 100))
        let framed = CanvasTransform.framing(rect, in: Vector2(800, 400), padding: 40)
        #expect(framed.zoom == 0.5)
        #expect(framed.toScreen(rect.centre) == Vector2(400, 200))
        #expect(framed.toScreen(rect.origin).x == 40)
    }

    @Test func framingKeepsTheZoomInRange() {
        let small = CanvasRect(origin: Vector2(100, 50), size: Vector2(200, 100))
        let zoomedIn = CanvasTransform.framing(small, in: Vector2(800, 400), padding: 40)
        #expect(zoomedIn.zoom == CanvasTransform.zoomRange.upperBound)
        #expect(zoomedIn.toScreen(small.centre) == Vector2(400, 200))
        let wide = CanvasRect(origin: .zero, size: Vector2(4000, 100))
        #expect(CanvasTransform.framing(wide, in: Vector2(800, 400), padding: 40).zoom == CanvasTransform.zoomRange.lowerBound)
    }

    @Test func fIsTheFrameKey() {
        func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
            KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
        }
        #expect(GraphKeyBindings.command(for: key("f"), paletteOpen: false) == .frameSelection)
        #expect(GraphKeyBindings.command(for: key("F", .shift), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("f", .command), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("f"), paletteOpen: true) == nil, "the palette's field types it")
    }

    @Test func fFramesTheSelectionInTheVisibleCanvas() {
        let editor = makeEditor([a, b])
        editor.selection = [b.id]
        editor.pointerLocation = Vector2(10, 10)
        #expect(editor.perform(.frameSelection))
        let canvas = editor.visibleCanvasSize
        let frame = editor.frame(of: b)
        #expect(close(editor.transform.toScreen(frame.centre), canvas * 0.5))
        let topLeft = editor.transform.toScreen(frame.origin)
        #expect(min(topLeft.x, topLeft.y) >= EditorModel.framingPadding - 1e-9)
        #expect(editor.transform.toScreen(Vector2(editor.frame(of: a).maxX, 0)).x < 0, "a isn't selected, so it is off screen")
    }

    @Test func withNothingSelectedFFramesEverything() {
        let editor = makeEditor([a, b])
        editor.pointerLocation = Vector2(10, 10)
        #expect(editor.perform(.frameSelection))
        let canvas = editor.visibleCanvasSize
        #expect(editor.transform.toScreen(editor.frame(of: a).origin).x >= EditorModel.framingPadding - 1e-9)
        #expect(editor.transform.toScreen(Vector2(editor.frame(of: b).maxX, 0)).x <= canvas.x - EditorModel.framingPadding + 1e-9)
    }

    /// Undo never prunes the selection: a selection whose nodes are all gone frames everything instead.
    @Test func fWithOnlyAStaleSelectionFramesEverything() {
        let editor = makeEditor([a, b])
        editor.pointerLocation = Vector2(10, 10)
        editor.perform(.frameSelection)
        let everything = editor.transform
        editor.transform = CanvasTransform()
        editor.selection = [nodeID(9)]
        #expect(editor.perform(.frameSelection))
        #expect(editor.transform == everything)
    }

    @Test func fNeedsThePointerOverTheVisibleCanvas() {
        let editor = makeEditor([a, b])
        editor.selection = [b.id]
        #expect(!editor.perform(.frameSelection), "the pointer is elsewhere: F is the viewport's")
        #expect(editor.transform == CanvasTransform())
        let hidden = makeEditor([a, b], dock: .hidden)
        hidden.pointerLocation = Vector2(10, 10)
        #expect(!hidden.perform(.frameSelection))
        let empty = makeEditor([])
        empty.pointerLocation = Vector2(10, 10)
        #expect(!empty.perform(.frameSelection), "nothing to frame: the key goes on")
    }

    /// Mid-drag F is claimed and does nothing: a new transform under a pan or a move would jump the canvas or the nodes.
    @Test func fDuringADragIsClaimedAndChangesNothing() {
        let editor = makeEditor([a, b])
        editor.pointerLocation = Vector2(10, 10)
        editor.middleDragged(from: Vector2(900, 600), to: Vector2(900, 600))
        editor.middleDragged(from: Vector2(900, 600), to: Vector2(920, 600))
        #expect(editor.perform(.frameSelection))
        #expect(editor.transform == CanvasTransform(offset: Vector2(20, 0), zoom: 1))
        editor.middleReleased(from: Vector2(900, 600), at: Vector2(920, 600))
    }

    @Test func fFramesTheLeftDocksTransposedLayout() {
        let editor = makeEditor([a, b], dock: .left)
        editor.selection = [b.id]
        editor.pointerLocation = Vector2(10, 10)
        editor.perform(.frameSelection)
        #expect(close(editor.transform.toScreen(editor.frame(of: b).centre), editor.visibleCanvasSize * 0.5))
        #expect(editor.frame(of: b).origin == Vector2(0, 1000))
    }
}
