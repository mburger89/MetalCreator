import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// What MetalUI drops without an end tells the graph canvas (C16 `onCancelled` and its synthesized scroll end, gap VI-a),
/// through the app's real window.
@MainActor
struct CanvasCancelWindowTests {
    func canvasPoint(_ app: AppWindow, _ x: Double, _ y: Double = 120) -> Point<Pixels> {
        app.point(inCanvasView: Vector2(x, y))
    }

    /// The middle button's release is lost; the next plain move tells MetalUI, which cancels the pan: the closed hand goes.
    @Test func aMiddlePanWhoseReleaseWasLostEndsAtThePointersNextMove() async throws {
        let app = try await AppWindow.open()
        let spot = canvasPoint(app, 400)
        app.window.hover(at: spot)
        _ = app.window.send(.otherMouseDown(MouseEvent(position: spot, buttonNumber: 2)))
        app.window.tick()
        _ = app.window.send(.otherMouseDragged(MouseEvent(position: canvasPoint(app, 440), buttonNumber: 2)))
        app.window.tick()
        #expect(app.editor.canvasCursor == .grabbing)
        _ = app.window.send(.mouseMoved(MouseEvent(position: canvasPoint(app, 460))))
        app.window.tick()
        #expect(app.editor.canvasCursor == nil && app.editor.interaction == nil)
    }

    /// A box under way when another element is pressed (the viewport here) is cancelled, and the selection it began with is
    /// put back.
    @Test func aBoxWhoseReleaseWasLostIsCancelledByThePressOnAnotherElement() async throws {
        let app = try await AppWindow.open()
        app.window.hover(at: canvasPoint(app, 600, 40))
        _ = app.window.send(.mouseDown(MouseEvent(position: canvasPoint(app, 600, 40))))
        app.window.tick()
        _ = app.window.send(.mouseDragged(MouseEvent(position: canvasPoint(app, 700, 100))))
        app.window.tick()
        guard case .boxSelecting? = app.editor.interaction else {
            Issue.record("expected a box")
            return
        }
        _ = app.window.send(.mouseDown(MouseEvent(position: Point(x: Pixels(700), y: Pixels(300)))))
        app.window.tick()
        #expect(app.editor.interaction == nil, "the cancelled press ended; the press on the viewport is not the canvas's")
    }

    /// A pinch the window cut short is cancelled, so the next pinch zooms from the canvas as it stands.
    @Test func aPinchCutShortByLosingKeyDoesntPullTheNextOneBack() async throws {
        let app = try await AppWindow.open()
        let spot = canvasPoint(app, 400)
        app.window.hover(at: spot)
        _ = app.window.send(.magnify(MagnifyEvent(position: spot, magnification: 0, phase: .began, timestamp: app.window.now)))
        app.window.tick()
        _ = app.window.send(.magnify(MagnifyEvent(position: spot, magnification: 0.5, phase: .changed, timestamp: app.window.now)))
        app.window.tick()
        let cut = app.editor.transform.zoom
        #expect(cut > 1 && app.editor.pinchStart != nil)
        app.window.setControlActiveState(.inactive)
        #expect(app.editor.pinchStart == nil)
        app.window.setControlActiveState(.key)
        app.window.magnify(at: spot, by: 2)
        #expect(abs(app.editor.transform.zoom - cut * 2) < 1e-9, "2× from the canvas as it stood")
    }

    /// A trackpad scroll the window cut short ends (MetalUI synthesizes the terminal event on key loss, `IF-H`), so the
    /// next scroll decides for itself whether it pans or zooms.
    @Test func aScrollCutShortByLosingKeyEndsAndTheNextOneDecidesAgain() async throws {
        let app = try await AppWindow.open()
        let spot = canvasPoint(app, 400)
        app.window.hover(at: spot)
        for phase in [InputPhase.began, .changed] {
            _ = app.window.send(.scrollWheel(ScrollEvent(
                position: spot, delta: Point(x: Pixels(0), y: Pixels(20)), modifiers: .command, phase: phase,
                momentumPhase: .none, isPrecise: true, timestamp: app.window.now)))
            app.window.tick()
        }
        #expect(app.editor.scrollZooms == true, "a ⌘-scroll under way zooms")
        app.window.setControlActiveState(.inactive)
        #expect(app.editor.scrollZooms == nil, "and is over")
    }

    /// A node dragged out of the library whose release was lost loses its ghost when another element is pressed, and
    /// nothing is added.
    @Test func aLibraryDragWhoseReleaseWasLostEndsWhenAnotherElementIsPressed() async throws {
        let app = try await AppWindow.open()
        app.editor.toggleLibrary()
        app.redraw()
        let table = try #require(app.window.elements(role: .table).first, "the library lists the node types")
        let row = Point(x: Pixels(table.frame.origin.x.value + 30), y: Pixels(table.frame.origin.y.value + 40))
        app.window.hover(at: row)
        _ = app.window.send(.mouseDown(MouseEvent(position: row)))
        app.window.tick()
        _ = app.window.send(.mouseDragged(MouseEvent(position: Point(x: Pixels(500), y: Pixels(700)))))
        app.window.tick()
        #expect(app.editor.libraryDrag != nil, "the ghost follows the pointer")
        let nodes = app.editor.graph.nodes.count
        _ = app.window.send(.mouseDown(MouseEvent(position: Point(x: Pixels(700), y: Pixels(300)))))
        app.window.tick()
        #expect(app.editor.libraryDrag == nil && app.editor.graph.nodes.count == nodes)
    }

    /// The panel's resize drag is cancelled with the press that lost its release, not left resizing for the next press.
    @Test func aPanelResizeWhoseReleaseWasLostEndsWhenAnotherElementIsPressed() async throws {
        let app = try await AppWindow.open()
        let edge = Point(x: Pixels(Float(app.size.x / 2)),
                         y: Pixels(Float(app.size.y - AppLayout.margin - app.model.panelHeight - AppLayout.resizeHandle / 2)))
        app.window.hover(at: edge)
        _ = app.window.send(.mouseDown(MouseEvent(position: edge)))
        app.window.tick()
        _ = app.window.send(.mouseDragged(MouseEvent(position: Point(x: edge.x, y: Pixels(edge.y.value - 20)))))
        app.window.tick()
        #expect(app.model.isResizingPanel)
        _ = app.window.send(.mouseDown(MouseEvent(position: Point(x: Pixels(700), y: Pixels(300)))))
        app.window.tick()
        #expect(!app.model.isResizingPanel)
    }
}
