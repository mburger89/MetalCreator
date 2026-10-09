import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import Testing
@testable import CreatorEditor

/// The add-node palette floats over the window (spec §6.2): placed under the pointer in window points, flipped
/// at the window's right and bottom edges, fixed in size, closed by a press outside it, and the node it adds still
/// lands at the canvas point where it opened.
@MainActor
struct FloatingPaletteTests {
    let size = PaletteLayout.size
    let window = Vector2(1000, 700)

    @Test func thePaletteIsAFixedSize() {
        #expect(size == Vector2(240, 292))
    }

    @Test func itsTopLeftCornerSitsAtThePointer() {
        #expect(PalettePlacement.origin(pointer: Vector2(100, 120), size: size, window: window) == Vector2(100, 120))
        #expect(PalettePlacement.origin(pointer: Vector2(100, 120), size: size, window: nil) == Vector2(100, 120))
    }

    @Test func itFlipsLeftAtTheRightEdge() {
        #expect(PalettePlacement.origin(pointer: Vector2(900, 120), size: size, window: window) == Vector2(660, 120))
    }

    @Test func itFlipsUpAtTheBottomEdge() {
        #expect(PalettePlacement.origin(pointer: Vector2(100, 600), size: size, window: window) == Vector2(100, 308))
    }

    @Test func itFlipsBothWaysInTheBottomRightCorner() {
        #expect(PalettePlacement.origin(pointer: Vector2(900, 600), size: size, window: window) == Vector2(660, 308))
    }

    /// Neither side fits: it is clamped inside the window's margins, and a window smaller than the palette keeps
    /// its top-left margin, so the search field stays reachable.
    @Test func itIsClampedWhenNeitherSideFits() {
        let small = Vector2(300, 320)
        #expect(PalettePlacement.origin(pointer: Vector2(150, 150), size: size, window: small) == Vector2(8, 8))
        #expect(PalettePlacement.origin(pointer: Vector2(250, 30), size: size, window: small) == Vector2(10, 8))
        #expect(PalettePlacement.origin(pointer: Vector2(150, 150), size: size, window: Vector2(100, 100)) == Vector2(8, 8))
    }

    /// Docked at the bottom, the panel is near the window's bottom, so the palette flips up over the viewport,
    /// fully visible, its bottom-left corner at the pointer, and the node still lands where Tab was pressed.
    @Test func atTheBottomDockItFlipsUpAndAddsAtThePressPoint() throws {
        let editor = makeEditor([], dock: .bottom)
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        editor.pointerLocation = Vector2(100, 50)
        editor.openPalette()
        let palette = try #require(editor.palette)
        let pointer = try #require(editor.canvasFrameInWindow).origin + Vector2(100, 50)
        #expect(palette.windowOrigin == Vector2(pointer.x, pointer.y - PaletteLayout.size.y))
        let frame = try #require(editor.paletteFrame)
        #expect(frame.origin.y >= 0 && frame.maxY <= 700 && frame.maxX <= 1000)
        editor.confirmPalette()
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.position == Vector2(100, 50), "at the canvas point under the pointer, not the palette's corner")
    }

    @Test func atTheLeftDockItOpensWithItsTopLeftCornerAtThePointer() throws {
        let editor = makeEditor([], dock: .left)
        let panel = CanvasRect(origin: Vector2(12, 68), size: Vector2(460, 820))
        editor.placement = { PanelPlacement(window: Vector2(1400, 900), panel: panel) }
        editor.pointerLocation = Vector2(50, 40)
        editor.openPalette()
        let canvas = try #require(editor.canvasFrameInWindow)
        #expect(canvas.origin.x > panel.origin.x && canvas.origin.y > panel.origin.y)
        #expect(editor.palette?.windowOrigin == canvas.origin + Vector2(50, 40))
    }

    @Test func aPressOutsideClosesItAndOneInsideDoesNot() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(100, 100)
        editor.openPalette()
        editor.windowPressed(at: Vector2(110, 110))
        #expect(editor.palette != nil)
        editor.windowPressed(at: Vector2(100 + 240 + 1, 110))
        #expect(editor.palette == nil)
        editor.windowPressed(at: Vector2(5, 5))
        #expect(editor.palette == nil, "nothing to close")
    }

    /// Any button's press reaching the window's `onInput` closes the palette when it is outside it (the primary, a
    /// right-click, the middle button), and is never claimed, so it goes on.
    @Test(arguments: ["primary", "secondary", "middle"])
    func theWindowsPressesReachThePaletteUnclaimed(_ button: String) {
        func press(_ x: Float, _ y: Float) -> InputEvent {
            let point = Point(x: Pixels(x), y: Pixels(y))
            switch button {
            case "secondary": return .rightMouseDown(MouseEvent(position: point, buttonNumber: 1))
            case "middle": return .otherMouseDown(MouseEvent(position: point, buttonNumber: 2))
            default: return .mouseDown(MouseEvent(position: point))
            }
        }
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        editor.pointerLocation = Vector2(100, 100)
        editor.openPalette()
        #expect(!input.handle(press(150, 150)))
        #expect(editor.palette != nil)
        #expect(!input.handle(press(900, 150)))
        #expect(editor.palette == nil)
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

    /// The panel no longer draws the palette (it can't clip or shift the canvas); the overlay draws it, at its
    /// window origin and at its fixed size.
    @Test func theOverlayDrawsThePaletteAndThePanelDoesNot() throws {
        let editor = sampleEditor(dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let closed = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        #expect(renderHeadless { SearchPaletteOverlay(model: editor) }.isEmpty, "nothing while closed")
        editor.pointerLocation = Vector2(300, 100)
        editor.openPalette()
        #expect(renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count == closed)
        let scene = renderHeadless { SearchPaletteOverlay(model: editor) }
        let origin = try #require(editor.palette?.windowOrigin)
        let glass = scene.rects.contains { rect in
            let placed = screenFrame(of: rect, in: scene)
            return (placed.origin - origin).length < 0.5 && (placed.size - PaletteLayout.size).length < 0.5
        }
        #expect(glass, "no \(PaletteLayout.size) glass at \(origin)")
    }
}
