import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// What MetalUI drops without an end tells its owner (C16 `onCancelled`, gap VI-a), through the app's real window: the
/// platform sequences that lose a gesture's end, driven as events. The viewport's drag, closed hand and pinch don't
/// outlive the gesture MetalUI dropped.
@MainActor
struct ViewportCancelWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport.
    let spot = Point(x: Pixels(700), y: Pixels(300))

    func at(_ dx: Float, _ dy: Float = 0) -> Point<Pixels> {
        Point(x: Pixels(700 + dx), y: Pixels(300 + dy))
    }

    func middleDrag(_ app: AppWindow, by dx: Float) {
        app.window.hover(at: spot)
        _ = app.window.send(.otherMouseDown(MouseEvent(position: spot, buttonNumber: 2)))
        app.window.tick()
        for step in 1...3 {
            _ = app.window.send(.otherMouseDragged(MouseEvent(position: at(dx * Float(step) / 3), buttonNumber: 2)))
            app.window.tick()
        }
    }

    /// The middle button's release is lost (Mission Control took it); the next plain move tells MetalUI, which cancels
    /// the drag (`IF-F` item 3): the pan ends and the arrow comes back.
    @Test func aMiddleDragWhoseReleaseWasLostEndsAtThePointersNextMove() async throws {
        let app = try await AppWindow.open()
        middleDrag(app, by: 30)
        #expect(app.model.viewport.activeDragMode == .pan && app.model.viewport.cursor == .grabbing)
        _ = app.window.send(.mouseMoved(MouseEvent(position: at(50))))
        app.window.tick()
        #expect(!app.model.viewport.isPointerDown && app.model.viewport.activeDragMode == nil)
        #expect(app.model.viewport.cursor == nil)
    }

    func primaryDrag(_ app: AppWindow) {
        app.window.hover(at: spot)
        _ = app.window.send(.mouseDown(MouseEvent(position: spot)))
        app.window.tick()
        for step in 1...3 {
            _ = app.window.send(.mouseDragged(MouseEvent(position: at(Float(step) * 10))))
            app.window.tick()
        }
    }

    /// A press on another element replaces a drag whose release never came: MetalUI cancels the old drag first.
    @Test func aPrimaryPressOnAnotherElementThatReplacesALostDragEndsIt() async throws {
        let app = try await AppWindow.open()
        primaryDrag(app)
        #expect(app.model.viewport.isPointerDown)
        _ = app.window.send(.mouseDown(MouseEvent(position: app.point(inCanvasView: Vector2(900, 120)))))
        app.window.tick()
        #expect(!app.model.viewport.isPointerDown, "the lost drag ended when the next press began")
    }

    /// Gap VI-b: a press on the same element continues MetalUI's arena, which drops the drag without a cancel. The viewport's
    /// own stopgap ends it when the next drag's values arrive (`ViewportModel.beginDragIfNeeded`).
    @Test func aPrimaryPressOnTheSameElementLeavesTheLostDragToTheNextDragValues() async throws {
        let app = try await AppWindow.open()
        let viewport = app.model.viewport
        primaryDrag(app)
        _ = app.window.send(.mouseDown(MouseEvent(position: at(0, 60))))
        app.window.tick()
        #expect(viewport.isPointerDown, "MetalUI told nobody (gap VI-b)")
        _ = app.window.send(.mouseUp(MouseEvent(position: at(0, 60))))
        app.window.tick()
        var settled = 0
        let previous = viewport.events.cameraSettled
        viewport.events.cameraSettled = { settled += 1; previous($0) }
        app.window.drag(from: at(100, 100), to: at(140, 100))
        #expect(!viewport.isPointerDown)
        #expect(settled == 2, "the lost drag settled where it was, then the new drag settled once")
    }

    /// A pinch the window cut short (⌘-Tab away mid-pinch) is cancelled, so a pinch at the same spot afterwards zooms from
    /// the camera as it stands, not from where the lost one began.
    @Test func aPinchCutShortByLosingKeyDoesntPullTheNextOneBack() async throws {
        let app = try await AppWindow.open()
        let viewport = app.model.viewport
        app.window.hover(at: spot)
        let start = viewport.pose.distance
        _ = app.window.send(.magnify(MagnifyEvent(position: spot, magnification: 0, phase: .began, timestamp: app.window.now)))
        app.window.tick()
        _ = app.window.send(.magnify(MagnifyEvent(position: spot, magnification: 0.5, phase: .changed, timestamp: app.window.now)))
        app.window.tick()
        let cut = viewport.pose.distance
        #expect(cut < start)
        app.window.setControlActiveState(.inactive)
        #expect(viewport.pinchStart == nil, "the cancelled pinch is over")
        app.window.setControlActiveState(.key)
        app.window.magnify(at: spot, by: 2)
        #expect(abs(viewport.pose.distance - cut / 2) < 1e-6 * cut, "2× from the camera as it stood, not from \(start)")
    }

    /// A trackpad scroll the window cut short settles the camera once (MetalUI synthesizes the scroll's terminal event on
    /// key loss, `IF-H`; the viewport's phase mapping turns it into the scroll's end): gap VI-a's last leftover.
    @Test func aScrollCutShortByLosingKeySettlesTheCamera() async throws {
        let app = try await AppWindow.open()
        let viewport = app.model.viewport
        app.window.hover(at: spot)
        for phase in [InputPhase.began, .changed] {
            _ = app.window.send(.scrollWheel(ScrollEvent(
                position: spot, delta: Point(x: Pixels(0), y: Pixels(20)), phase: phase, momentumPhase: .none,
                isPrecise: true, timestamp: app.window.now)))
            app.window.tick()
        }
        #expect(viewport.scrollStartPose != nil, "the scroll is under way")
        app.window.setControlActiveState(.inactive)
        #expect(viewport.scrollStartPose == nil, "and over, with the camera settled")
    }
}
