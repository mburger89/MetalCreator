import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// A trackpad pinch over the graph canvas (spec §6.2, docs/metalui-gaps.md M5-f) zooms about where it began.
@MainActor
struct CanvasPinchTests {
    let centre = Vector2(240, 120)

    @Test func aPinchZoomsByItsCumulativeMagnificationAboutItsCentre() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 1)
        let under = editor.transform.toCanvas(centre)
        editor.pinchChanged(magnification: 1.2, centre: centre)
        editor.pinchChanged(magnification: 1.5, centre: centre)
        #expect(abs(editor.transform.zoom - 1.5) < 1e-12, "cumulative from the pinch's start, not compounded")
        #expect((editor.transform.toCanvas(centre) - under).length < 1e-9)
        editor.pinchEnded()
        editor.pinchChanged(magnification: 2, centre: centre)
        #expect(abs(editor.transform.zoom - 3) < 1e-12, "the next pinch zooms from where this one left it")
        #expect(!editor.document.canUndo, "zooming is not an edit")
    }

    @Test func aHardPinchInHoldsInsteadOfSpringingBack() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(zoom: 2)
        editor.pinchChanged(magnification: 0.5, centre: centre)
        editor.pinchChanged(magnification: -0.3, centre: centre)
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.lowerBound)
        editor.pinchChanged(magnification: 0, centre: centre)
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.lowerBound)
        #expect(editor.transform.offset.isFinite)
    }

    @Test func aNonFinitePinchChangesNothing() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 1.5)
        let before = editor.transform
        editor.pinchChanged(magnification: .nan, centre: centre)
        editor.pinchChanged(magnification: .infinity, centre: centre)
        editor.pinchChanged(magnification: 1.2, centre: Vector2(.infinity, 0))
        #expect(editor.transform == before)
    }

    /// MetalUI drops a pinch that lost its end (a new pinch replaced it, the window stopped being key) and tells the
    /// gesture's owner (`onCancelled`, C16, gap VI-a: `pinchEnded()`); the next one, at any centre, zooms from the canvas
    /// as it is, not from where the cancelled one began, and not over a pan or a zoom made since.
    @Test(arguments: [Vector2(400, 300), Vector2(200, 150)])
    func aCancelledPinchDoesntPullTheNextOneBack(next: Vector2) {
        let editor = makeEditor([])
        editor.pinchChanged(magnification: 2, centre: centre)
        editor.middleDrag(Vector2(600, 600), Vector2(640, 620))
        editor.zoom(in: true)
        let moved = editor.transform
        editor.pinchEnded()
        editor.pinchChanged(magnification: 1.25, centre: next)
        #expect(editor.transform == moved.zoomed(by: 1.25, around: next))
    }

    @Test func aPinchEndedWithNoPinchChangesNothing() {
        let editor = makeEditor([])
        let before = editor.transform
        editor.pinchEnded()
        #expect(editor.transform == before && editor.pinchStart == nil)
    }

    @Test func aPinchClosesThePalette() {
        let editor = makeEditor([])
        editor.pointerLocation = centre
        editor.openPalette()
        editor.pinchChanged(magnification: 1.1, centre: centre)
        #expect(editor.palette == nil)
    }
}
