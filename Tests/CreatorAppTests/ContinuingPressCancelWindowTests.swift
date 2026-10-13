import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorViewport

/// A primary press that arrives while the arena is still pressing (the release went to Mission Control or a native menu) is
/// a lost release to MetalUI C26 (`GC-B`, `GC-C`): it abandons that arena through `cancel()`, so a drag that had reported gets
/// `onCancelled` once, and a fresh arena forms for the new press. These run the app's real window, press on the same element
/// twice, and look before any drag value of the second press arrives, which is the proof that no model stopgap is needed
/// (docs/metalui-gaps.md VI-b): the viewport's and the canvas's drag, a handle edit's end and the closed hand end at the press.
@MainActor
struct ContinuingPressCancelWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport.
    func spot(_ dx: Float, _ dy: Float = 0) -> Point<Pixels> {
        Point(x: Pixels(700 + dx), y: Pixels(300 + dy))
    }

    func press(_ app: AppWindow, at point: Point<Pixels>) {
        _ = app.window.send(.mouseDown(MouseEvent(position: point)))
        app.window.tick()
    }

    func move(_ app: AppWindow, to point: Point<Pixels>) {
        _ = app.window.send(.mouseDragged(MouseEvent(position: point)))
        app.window.tick()
    }

    func release(_ app: AppWindow, at point: Point<Pixels>) {
        _ = app.window.send(.mouseUp(MouseEvent(position: point)))
        app.window.tick()
    }

    // MARK: - The viewport

    /// A handle edit whose release was lost ends at the next press on the viewport, with the phase `.ended` reported once and
    /// the value it got to kept as one undo step; the press that ended it then starts an ordinary orbit.
    @Test func aHandleEditWhoseReleaseWasLostEndsAtTheNextPressOnTheViewport() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = try await AppWindow.open(builder.graph)
        let viewport = app.model.viewport
        app.editor.selection = [box.extrude.id]
        await app.model.settle()
        app.redraw()
        let handle = try #require(viewport.handles.first)
        let knob = try #require(CameraMath.project(handle.knob, viewport.pose, size: viewport.viewSize)).point
        var phases: [HandleDragPhase] = []
        let previous = viewport.events.handleChanged
        viewport.events.handleChanged = { phases.append($2); previous($0, $1, $2) }
        let start = Point(x: Pixels(Float(knob.x)), y: Pixels(Float(knob.y)))
        press(app, at: start)
        for step in 1...4 {
            move(app, to: Point(x: Pixels(start.x.value), y: Pixels(start.y.value - Float(step) * 8)))
        }
        #expect(viewport.activeDragMode == .handle(handle.id) && phases.last == .changed)
        let edited = try #require(app.model.document.graph.nodes[box.extrude.id]?.inputValues["distance"])
        #expect(edited != .number(10), "the drag moved the value")
        press(app, at: spot(100, 100))
        #expect(viewport.activeDragMode == nil && !viewport.isPointerDown)
        #expect(phases.filter { $0 == .ended }.count == 1, "the edit's end came from the cancel, once")
        release(app, at: spot(100, 100))
        #expect(phases.filter { $0 == .ended }.count == 1, "the late release ends nothing again")
        #expect(app.model.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == edited, "the edit is kept")
        app.model.document.undo()
        #expect(app.model.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(10), "as one undo step")
    }

    /// Gap VI-c: MetalUI cancels a button arena at the pointer's next plain move (`IF-F` item 3) but not the primary arena (its
    /// ruling `GC-C` leaves the bare move alone, as SwiftUI does), so a lost primary release leaves the drag, its closed hand and
    /// its unsettled camera in place until the next press ends them. Accepted (gap VI-c) and pinned here.
    @Test func aPlainMoveDoesntEndALostPrimaryDragOnlyTheNextPressDoes() async throws {
        let app = try await AppWindow.open()
        let viewport = app.model.viewport
        app.window.hover(at: spot(0))
        press(app, at: spot(0))
        for step in 1...3 { move(app, to: spot(Float(step) * 10)) }
        _ = app.window.send(.mouseMoved(MouseEvent(position: spot(60, 20))))
        app.window.tick()
        #expect(viewport.isPointerDown && viewport.cursor == .grabbing, "gap VI-c: the move ended nothing")
        press(app, at: spot(60, 20))
        #expect(!viewport.isPointerDown && viewport.cursor == nil, "the press did")
    }

    /// A real double click (platform count 2) over the viewport fires no cancel: it settles nothing, ends no drag and reports
    /// two clicks, as it did before C26 (`GC2`: the continuing branch is kept for a press that finds the arena released).
    @Test func aDoubleClickOverTheViewportCancelsNothing() async throws {
        let app = try await AppWindow.open()
        let viewport = app.model.viewport
        var settled = 0
        var clicks = 0
        let previous = viewport.events.cameraSettled
        viewport.events.cameraSettled = { settled += 1; previous($0) }
        let previousClick = viewport.events.clicked
        viewport.events.clicked = { clicks += 1; previousClick($0) }
        app.window.doubleClick(at: spot(0, 60))
        #expect(settled == 0 && !viewport.isPointerDown)
        #expect(clicks == 2, "both clicks arrive as clicks")
    }

    // MARK: - The canvas

    func canvas(_ app: AppWindow, _ x: Double, _ y: Double = 120) -> Point<Pixels> {
        app.point(inCanvasView: Vector2(x, y))
    }

    /// A box whose release was lost is cancelled by the next press on the canvas: the selection it began with is put back
    /// before any value of the new press arrives, the late release is that press's own click, and the new drag, a box again,
    /// starts from the new press after the canvas's own 3-point threshold.
    @Test func aBoxWhoseReleaseWasLostIsCancelledByTheNextPressOnTheCanvas() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = try await AppWindow.open(builder.graph)
        let editor = app.editor
        editor.selection = [box.output.id]
        let from = canvas(app, 600, 160)
        press(app, at: from)
        move(app, to: canvas(app, 760, 220))
        guard case .boxSelecting? = editor.interaction else {
            Issue.record("expected a box")
            return
        }
        #expect(editor.selection != [box.output.id], "the box replaced the selection")
        press(app, at: canvas(app, 620, 170))
        #expect(editor.interaction == nil, "the cancel ended the box at the press")
        #expect(editor.selection == [box.output.id], "and put the selection back")
        move(app, to: canvas(app, 621, 170))
        #expect(editor.interaction == nil, "1 point is under the canvas's 3-point threshold")
        move(app, to: canvas(app, 700, 210))
        guard case .boxSelecting(let origin, _, _, _)? = editor.interaction else {
            Issue.record("expected a fresh box")
            return
        }
        #expect(origin == editor.transform.toCanvas(Vector2(620, 170)), "from the new press, not the lost one")
        release(app, at: canvas(app, 700, 210))
        #expect(editor.interaction == nil)
    }

    /// A node move whose release was lost stays where it got to and its undo step ends at the next press on the canvas; that
    /// press is a plain click on empty canvas, which clears the selection.
    @Test func aNodeMoveWhoseReleaseWasLostEndsAtTheNextPressOnTheCanvas() async throws {
        var builder = GraphBuilder()
        let sketched = builder.sketchedBox()
        let app = try await AppWindow.open(builder.graph)
        let editor = app.editor
        let node = sketched.sketch.id
        let origin = try #require(app.model.document.graph.nodes[node]?.position)
        let spot = app.point(inCanvas: Vector2(60, 40))
        press(app, at: spot)
        move(app, to: Point(x: Pixels(spot.x.value + 40), y: Pixels(spot.y.value)))
        guard case .moving? = editor.interaction else {
            Issue.record("expected a move")
            return
        }
        let moved = try #require(app.model.document.graph.nodes[node]?.position)
        #expect(moved != origin)
        let empty = canvas(app, 20, 200)
        press(app, at: empty)
        #expect(editor.interaction == nil, "the move ended at the press")
        #expect(app.model.document.graph.nodes[node]?.position == moved, "and stayed where it got to")
        release(app, at: empty)
        #expect(editor.selection.isEmpty, "the new press, released, is a click on empty canvas")
        app.model.document.undo()
        #expect(app.model.document.graph.nodes[node]?.position == origin, "the lost move was one undo step")
    }
}
