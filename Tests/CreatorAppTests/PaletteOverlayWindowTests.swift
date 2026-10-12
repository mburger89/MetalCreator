import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The add-node palette as MetalUI's `anchoredOverlay` (gaps EP-a and EP-b), through the app's real window: where it
/// opens and how it flips at the window's edges, and what closes it. The palette's own keys are
/// `PaletteKeyRoutingWindowTests`'s (F, + and − typed into its field; Escape closing it with the field focused).
@MainActor
struct PaletteOverlayWindowTests {
    /// A Rectangle node at (40, 40), so the canvas has something to click and the inspector has fields.
    func open(dock: DockSide = .bottom) async throws -> (app: AppWindow, rectangle: Node) {
        var builder = GraphBuilder()
        let part = builder.box(at: Vector2(40, 40))
        return (try await AppWindow.open(builder.graph, dock: dock), part.rectangle)
    }

    /// Opens the palette with Space, the pointer at `local` on the canvas; returns the pointer.
    @discardableResult
    func openPalette(_ app: AppWindow, at local: Vector2) async throws -> Point<Pixels> {
        let pointer = app.point(inCanvasView: local)
        app.window.hover(at: pointer)
        app.window.typeKey(.space)
        try await app.window.runUntilIdle()
        try #require(app.editor.palette != nil, "Space over the canvas opens the palette")
        return pointer
    }

    /// Opens it, and returns the pointer and the palette's frame in the window.
    func openAndMeasure(_ app: AppWindow, at local: Vector2) async throws -> (pointer: Point<Pixels>, frame: Bounds<Pixels>) {
        let pointer = try await openPalette(app, at: local)
        return (pointer, try #require(app.palettePanel).frame)
    }

    let width = Float(PaletteLayout.size.x), height = Float(PaletteLayout.size.y)

    // MARK: - Where it opens (gap EP-a)

    /// Before the viewport has drawn once (in this headless window it never does) the palette is still exactly at the
    /// pointer: the pointer's window point comes from the canvas's `.global` hover, not from a placement.
    @Test func itOpensWithItsTopLeftCornerAtThePointerWhateverTheViewportHasDrawn() async throws {
        let (app, _) = try await open(dock: .left)
        let (pointer, frame) = try await openAndMeasure(app, at: Vector2(120, 90))
        #expect(frame.origin == pointer)
        #expect(frame.size == Size(width: Pixels(width), height: Pixels(height)))
        #expect(app.editor.palette?.screenPosition == Vector2(120, 90), "and the node would land at the canvas point")
    }

    /// A bottom-docked canvas runs to the window's right edge and sits at its bottom, so a pointer near the canvas's
    /// bottom-right corner flips the palette both ways: its bottom-right corner is at the pointer.
    @Test func itFlipsLeftAtTheRightEdgeAndUpAtTheBottom() async throws {
        let (app, _) = try await open(dock: .bottom)
        let (pointer, frame) = try await openAndMeasure(app, at: Vector2(app.canvasFrame.size.x - 30, 40))
        #expect(frame.origin.x + frame.size.width == pointer.x, "its right edge is at the pointer")
        #expect(frame.origin.y + frame.size.height == pointer.y, "its bottom edge is at the pointer")
    }

    /// A left-docked canvas has room to its right, but not below its bottom: only the vertical axis flips.
    @Test func itFlipsUpAtTheBottomEdgeAndOnlyThere() async throws {
        let (app, _) = try await open(dock: .left)
        let (pointer, frame) = try await openAndMeasure(app, at: Vector2(60, app.canvasFrame.size.y - 30))
        #expect(frame.origin.x == pointer.x, "it still opens to the pointer's right")
        #expect(frame.origin.y + frame.size.height == pointer.y, "its bottom edge is at the pointer")
    }

    /// Resizing the window while the palette is open re-places it inside the new window, as MetalUI's own overlays are.
    @Test func resizingTheWindowWhileOpenKeepsItInside() async throws {
        let (app, _) = try await open(dock: .bottom)
        let (_, before) = try await openAndMeasure(app, at: Vector2(app.canvasFrame.size.x - 30, 100))
        app.window.resize(to: Size(width: Pixels(1000), height: Pixels(700)))
        try await app.window.runUntilIdle()
        let after = try #require(app.palettePanel).frame
        #expect(after.origin.x + after.size.width <= 1000 && after.origin.y + after.size.height <= 700)
        #expect(after.origin.x != before.origin.x, "it moved with the window")
        #expect(app.editor.palette != nil, "and stays open")
    }

    // MARK: - What closes it (gap EP-b)

    /// The stopgap could not see a press into a text field: the field claimed it first. The press closes the palette
    /// and still lands, so the field has the focus.
    @Test func aPressIntoATextFieldClosesItAndTheFieldGetsFocus() async throws {
        let (app, rectangle) = try await open()
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        try #require(app.editor.selection == [rectangle.id])
        try await openPalette(app, at: Vector2(app.canvasFrame.size.x - 400, 60))
        let field = try #require(app.window.elements {
            $0.role == .textField && $0.label != "Add node" && $0.frame.origin.x.value >= Float(app.inspectorColumnStart)
        }.first)
        try app.window.click(field)
        #expect(app.editor.palette == nil)
        #expect(try app.window.focusedElement?.frame == field.frame, "the press landed: the field has the focus")
    }

    /// The stopgap could not see a press onto a slider either: the slider claimed it first. The press closes the palette
    /// and still lands, so the slider takes the drag (one undo step, as it does without a palette).
    @Test func aPressOntoASliderClosesItAndTheSliderStillMoves() async throws {
        let (app, rectangle) = try await open()
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        try #require(app.editor.selection == [rectangle.id])
        try await openPalette(app, at: Vector2(app.canvasFrame.size.x - 400, 60))
        let slider = try #require(app.window.elements(role: .slider).first)
        let y = slider.frame.origin.y + slider.frame.size.height / 2
        let width = slider.frame.size.width.value
        app.window.drag(from: Point(x: slider.frame.origin.x + Pixels(width * 0.1), y: y),
                        to: Point(x: slider.frame.origin.x + Pixels(width * 0.9), y: y), steps: 6)
        #expect(app.editor.palette == nil)
        #expect(app.editor.graph.nodes[rectangle.id]?.inputValues["width"] != nil, "the slider took the drag")
        #expect(app.editor.document.undoName == "Change Width")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[rectangle.id]?.inputValues["width"] == nil, "one undo undoes the whole drag")
        #expect(!app.editor.document.canUndo)
    }

    /// A right-click that opens the viewport's context menu was claimed before the stopgap saw it.
    @Test func aRightClickThatOpensAContextMenuClosesItAndTheMenuStillOpens() async throws {
        let (app, _) = try await open()
        try await openPalette(app, at: Vector2(900, 120))
        app.window.rightClick(at: app.point(inCanvasView: Vector2(300, 150)))
        #expect(app.editor.palette == nil)
        #expect(app.window.presentedMenu != nil, "the press went on to the canvas, whose context menu opens")
    }

    @Test func aRightClickOnTheViewportClosesIt() async throws {
        let (app, _) = try await open()
        try await openPalette(app, at: Vector2(900, 120))
        app.window.rightClick(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.editor.palette == nil)
    }

    /// Escape with the search field focused and a node selected: the palette closes and the selection is untouched.
    @Test func escapeClosesItAndLeavesTheSelectionAlone() async throws {
        let (app, rectangle) = try await open()
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        try #require(app.editor.selection == [rectangle.id])
        try await openPalette(app, at: Vector2(900, 120))
        app.window.typeText("Box")
        app.window.typeKey(.escape)
        try await app.window.runUntilIdle()
        #expect(app.editor.palette == nil)
        #expect(app.editor.selection == [rectangle.id])
    }

    @Test func aPressOnTheCanvasClosesItAndSelectsWhatItHit() async throws {
        let (app, rectangle) = try await open()
        try await openPalette(app, at: Vector2(900, 120))
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.palette == nil)
        #expect(app.editor.selection == [rectangle.id], "the press reached the canvas as well")
    }

    @Test func aPressOnTheViewportClosesIt() async throws {
        let (app, _) = try await open()
        try await openPalette(app, at: Vector2(900, 120))
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.editor.palette == nil)
    }

    @Test(arguments: [false, true])
    func theRightAndMiddleButtonsOutsideCloseItToo(middle: Bool) async throws {
        let (app, _) = try await open()
        try await openPalette(app, at: Vector2(900, 120))
        let outside = app.point(inCanvasView: Vector2(300, 150))
        if middle { app.window.otherClick(at: outside) } else { app.window.rightClick(at: outside) }
        #expect(app.editor.palette == nil)
    }

    @Test func aPressOnItsOwnGlassStaysOpenAndNothingBeneathReacts() async throws {
        let (app, _) = try await open(dock: .left)
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        let (_, frame) = try await openAndMeasure(app, at: Vector2(120, 90))
        let padding = Point(x: frame.origin.x + Pixels(3), y: frame.origin.y + Pixels(3))
        app.window.click(at: padding)
        #expect(app.editor.palette != nil)
        #expect(app.editor.selection.isEmpty && app.editor.transform == transform && app.model.viewport.pose == pose)
    }

    // MARK: - The wheel and the pinch on it

    @Test func aScrollOverItDoesNotReachTheCanvasOrTheViewport() async throws {
        let (app, _) = try await open(dock: .left)
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        // Over the canvas.
        let (_, frame) = try await openAndMeasure(app, at: Vector2(60, 60))
        let middle = Point(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
        app.window.scroll(at: middle, byDeltaX: 0, deltaY: 40)
        #expect(app.editor.transform == transform, "the canvas did not pan")
        #expect(app.editor.palette != nil, "and the palette stays open")
        // Over the viewport: the palette reaches out of the canvas's right edge.
        app.editor.closePalette()
        let edge = Vector2(app.canvasFrame.size.x - 30, 60)
        let (_, flipped) = try await openAndMeasure(app, at: edge)
        let over = Point(x: flipped.origin.x + flipped.size.width / 2, y: flipped.origin.y + flipped.size.height / 2)
        app.window.scroll(at: over, byDeltaX: 0, deltaY: 40)
        #expect(app.model.viewport.pose == pose, "the viewport did not zoom")
        #expect(app.editor.palette != nil)
    }

    /// Outside it the wheel is the canvas's as before: it pans, and (the model's rule) that closes the palette.
    @Test func aScrollOutsideItStillMovesTheCanvasAndClosesIt() async throws {
        let (app, _) = try await open(dock: .left)
        let transform = app.editor.transform
        try await openPalette(app, at: Vector2(60, 60))
        app.window.scroll(at: app.point(inCanvasView: Vector2(380, 500)), byDeltaX: 0, deltaY: 40)
        #expect(app.editor.transform != transform)
        #expect(app.editor.palette == nil)
    }

    /// Human check GI-7: a pinch over the palette moves neither the canvas nor the viewport, and it stays open.
    @Test func aPinchOverItMovesNothingAndItStaysOpen() async throws {
        let (app, _) = try await open(dock: .left)
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        let (_, frame) = try await openAndMeasure(app, at: Vector2(60, 60))
        app.window.magnify(at: Point(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2), by: 0.5)
        #expect(app.editor.palette != nil)
        #expect(app.editor.transform == transform && app.model.viewport.pose == pose)
    }
}
