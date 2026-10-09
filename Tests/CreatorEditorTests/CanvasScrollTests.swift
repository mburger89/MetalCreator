import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorEditor

/// Scrolling over the graph canvas (spec §6.2, docs/metalui-gaps.md M5-f): two-finger scroll and the wheel pan
/// it, with the glide after a flick; ⌘-scroll zooms about the pointer, without a glide.
@MainActor
struct CanvasScrollTests {
    @Test func aWheelStepPansTheCanvasByItsDelta() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        #expect(editor.scrolled(by: Vector2(10, -20), at: Vector2(100, 100), modifiers: [], phase: .step))
        #expect(editor.transform == CanvasTransform(offset: Vector2(15, -15), zoom: 2))
        #expect(editor.document.viewState.canvasOffset == Vector2(15, -15))
        #expect(!editor.document.canUndo, "panning is not an edit")
    }

    @Test func aTrackpadScrollPansAndItsGlideKeepsPanning() {
        let editor = makeEditor([])
        editor.scrolled(by: .zero, at: Vector2(100, 100), modifiers: [], phase: .began)
        editor.scrolled(by: Vector2(4, 6), at: Vector2(100, 100), modifiers: [], phase: .changed)
        editor.scrolled(by: .zero, at: Vector2(100, 100), modifiers: [], phase: .ended)
        editor.scrolled(by: Vector2(2, 3), at: Vector2(100, 100), modifiers: [], phase: .momentum)
        #expect(editor.transform == CanvasTransform(offset: Vector2(6, 9), zoom: 1))
    }

    @Test func commandScrollZoomsAboutThePointer() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(10, 10), zoom: 1)
        let pointer = Vector2(200, 100)
        let under = editor.transform.toCanvas(pointer)
        editor.scrolled(by: Vector2(3, 10), at: pointer, modifiers: .command, phase: .step)
        #expect(abs(editor.transform.zoom - exp(0.1)) < 1e-12)
        #expect((editor.transform.toCanvas(pointer) - under).length < 1e-9, "the point under the pointer stays put")
        editor.scrolled(by: Vector2(0, -10), at: pointer, modifiers: .command, phase: .step)
        #expect(abs(editor.transform.zoom - 1) < 1e-12, "scrolling back zooms back out")
    }

    /// The glide after a ⌘-scroll is ignored, also once ⌘ is let go: it would pan the canvas the user just zoomed.
    @Test func aZoomScrollsGlideIsIgnored() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 20), at: pointer, modifiers: .command, phase: .changed)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .ended)
        let zoomed = editor.transform
        #expect(zoomed.zoom > 1)
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: [], phase: .momentum)
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: .command, phase: .momentum)
        #expect(editor.transform == zoomed)
    }

    /// A zoom's glide is ignored until its momentum ends; a glide after that (one drifting in from a pan elsewhere)
    /// pans.
    @Test func aZoomsGlideIsIgnoredOnlyUntilItsMomentumEnds() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 20), at: pointer, modifiers: .command, phase: .changed)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .ended)
        let zoomed = editor.transform
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: [], phase: .momentum)
        editor.scrolled(by: Vector2(0, 1), at: pointer, modifiers: [], phase: .momentumEnded)
        #expect(editor.transform == zoomed)
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: [], phase: .momentum)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 8)))
    }

    /// MetalUI sends each scroll event to what is under the pointer at that event (gap GI-b), so a scroll that began
    /// over something else reaches the canvas with a `.changed` and no `.began`. It is taken up as it is then (no ⌘:
    /// a pan), never as the last canvas scroll was (a zoom), and keeps that until it ends.
    @Test func aScrollThatBeganElsewhereIsTakenUpAsItIsNow() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 20), at: pointer, modifiers: .command, phase: .changed)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .ended)
        let zoomed = editor.transform
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: [], phase: .changed)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 10)))
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: .command, phase: .changed)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 20)), "⌘ pressed after it was taken up changes nothing")
    }

    /// A trackpad scroll keeps doing what it began doing: ⌘ pressed or let go part-way changes nothing.
    @Test func aTrackpadScrollZoomsOrPansAsItBegan() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: [], phase: .began)
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: .command, phase: .changed)
        #expect(editor.transform == CanvasTransform(offset: Vector2(0, 10), zoom: 1))
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: [], phase: .changed)
        #expect(editor.transform.zoom > 1)
        // A wheel step decides for itself, whatever the last trackpad scroll did.
        let zoomed = editor.transform
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: [], phase: .step)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 10)))
    }

    @Test func theScrollZoomStaysInRange() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        for _ in 0..<40 { editor.scrolled(by: Vector2(0, 100), at: pointer, modifiers: .command, phase: .step) }
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.upperBound)
        for _ in 0..<80 { editor.scrolled(by: Vector2(0, -100), at: pointer, modifiers: .command, phase: .step) }
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.lowerBound)
        #expect(editor.transform.offset.isFinite)
    }

    @Test func aNonFiniteScrollChangesNothing() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        let before = editor.transform
        #expect(editor.scrolled(by: Vector2(.nan, 4), at: Vector2(10, 10), modifiers: [], phase: .step))
        editor.scrolled(by: Vector2(0, .infinity), at: Vector2(10, 10), modifiers: .command, phase: .step)
        editor.scrolled(by: Vector2(0, 10), at: Vector2(.infinity, 10), modifiers: .command, phase: .step)
        #expect(editor.transform == before)
    }

    /// The palette adds at the canvas point it opened over, so a scroll that moves the canvas closes it.
    @Test func aScrollThatMovesTheCanvasClosesThePalette() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(100, 100)
        editor.openPalette()
        editor.scrolled(by: .zero, at: Vector2(100, 100), modifiers: [], phase: .began)
        #expect(editor.palette != nil, "a scroll that doesn't move the canvas leaves it open")
        editor.scrolled(by: Vector2(0, 12), at: Vector2(100, 100), modifiers: [], phase: .changed)
        #expect(editor.palette == nil)
    }
}
