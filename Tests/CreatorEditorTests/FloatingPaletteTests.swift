import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import Testing
@testable import CreatorEditor

/// The add-node palette floats over the window (spec §6.2): it opens at the pointer's window point, is a fixed size,
/// and the node it adds still lands at the canvas point where it opened. Where it is drawn, flipped at the window's
/// edges and closed by a press outside, is MetalUI's `anchoredOverlay` (gaps EP-a and EP-b): `PaletteOverlayWindowTests`
/// pins it through the app's real window.
@MainActor
struct FloatingPaletteTests {
    @Test func thePaletteIsAFixedSize() {
        #expect(PaletteLayout.size == Vector2(240, 292))
    }

    /// The canvas's `.global` hover says where the pointer is in the window, which is where the palette opens, with no
    /// placed panel and no drawn viewport needed.
    @Test func itOpensAtThePointersWindowPoint() {
        let editor = makeEditor([], dock: .bottom)
        editor.pointerLocation = Vector2(100, 50)
        editor.pointerWindowLocation = Vector2(412, 700)
        editor.openPalette()
        #expect(editor.palette?.windowPoint == Vector2(412, 700))
        #expect(editor.palette?.screenPosition == Vector2(100, 50), "and the node lands at the canvas point")
    }

    /// Without a hovered window point (a test, a key pressed before the first hover reached the model) the canvas point
    /// is moved into the window with the panel's placement, and without that it is used as it is.
    @Test func withoutAWindowPointItIsTheCanvasPointInWindowCoordinates() throws {
        let editor = makeEditor([], dock: .left)
        editor.pointerLocation = Vector2(50, 40)
        editor.openPalette()
        #expect(editor.palette?.windowPoint == Vector2(50, 40), "unplaced")
        let panel = CanvasRect(origin: Vector2(12, 68), size: Vector2(460, 820))
        editor.panelPlacement = PanelPlacement(window: Vector2(1400, 900), panel: panel)
        editor.openPalette()
        let canvas = try #require(editor.canvasFrameInWindow)
        #expect(editor.palette?.windowPoint == canvas.origin + Vector2(50, 40))
    }

    /// A key pressed with the pointer not over the canvas opens it at the canvas's corner, not at a stale window point.
    @Test func withNoPointerOverTheCanvasItIgnoresAStaleWindowPoint() {
        let editor = makeEditor([], dock: .left)
        editor.pointerWindowLocation = Vector2(900, 500)
        editor.openPalette()
        #expect(editor.palette?.screenPosition == Vector2(24, 24))
        #expect(editor.palette?.windowPoint == Vector2(24, 24))
    }

    /// The node still lands at the canvas point where Tab was pressed, not at the palette's corner.
    @Test func theNodeItAddsLandsAtThePressPoint() throws {
        let editor = makeEditor([], dock: .bottom)
        editor.panelPlacement = PanelPlacement(window: Vector2(1000, 700),
                                               panel: CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300)))
        editor.pointerLocation = Vector2(100, 50)
        editor.pointerWindowLocation = Vector2(300, 500)
        editor.openPalette()
        editor.confirmPalette()
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.position == Vector2(100, 50), "at the canvas point under the pointer, not the palette's corner")
    }

    /// The canvas's container reports the pointer in window points, and the pointer leaving clears it.
    @Test func theGlobalHoverFeedsTheModel() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        input.windowHover(.active(Point(x: Pixels(412), y: Pixels(700))))
        #expect(editor.pointerWindowLocation == Vector2(412, 700))
        input.windowHover(.ended)
        #expect(editor.pointerWindowLocation == nil)
    }

    /// With more matches than rows, ↑/↓ scroll the rows to keep the highlight in view, and typing starts over.
    @Test func theRowsScrollToKeepTheHighlightInView() {
        let editor = makeEditor([], registry: BuiltInNodes.registry)
        editor.openPalette()
        let all = editor.paletteEntries
        #expect(all.count > PaletteLayout.visibleRows)
        #expect(editor.paletteVisibleEntries == Array(all.prefix(PaletteLayout.visibleRows)))
        #expect(editor.paletteHiddenCount == all.count - PaletteLayout.visibleRows)
        editor.movePaletteHighlight(by: 12)
        #expect(editor.palette?.highlighted == 12)
        #expect(editor.palette?.firstVisible == 3)
        #expect(editor.paletteVisibleEntries.last == all[12])
        editor.movePaletteHighlight(by: -11)
        #expect(editor.palette?.firstVisible == 1)
        #expect(editor.paletteVisibleEntries.first == all[1])
        editor.setPaletteQuery("ex")
        #expect(editor.palette?.firstVisible == 0)
        #expect(editor.paletteHiddenCount == 0)
    }

    /// The panel no longer draws the palette (it can't clip or shift the canvas); the overlay draws it, at the point it
    /// opened at and at its fixed size.
    @Test func theOverlayDrawsThePaletteAndThePanelDoesNot() throws {
        let editor = sampleEditor(dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let closed = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        #expect(renderHeadless { SearchPaletteOverlay(model: editor) }.isEmpty, "nothing while closed")
        editor.pointerLocation = Vector2(300, 100)
        editor.openPalette()
        #expect(renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count == closed)
        let scene = renderHeadless { SearchPaletteOverlay(model: editor) }
        let origin = try #require(editor.palette?.windowPoint)
        let glass = scene.rects.contains { rect in
            let placed = screenFrame(of: rect, in: scene)
            return (placed.origin - origin).length < 0.5 && (placed.size - PaletteLayout.size).length < 0.5
        }
        #expect(glass, "no \(PaletteLayout.size) glass at \(origin)")
    }
}
