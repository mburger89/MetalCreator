import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorViewport

/// A trackpad scroll goes where its `.began` went, glide included (MetalUI C16, gap GI-b), through the app's real window:
/// a flick that pans the graph canvas keeps panning it when the pointer drifts onto the viewport, and the viewport's zoom
/// does not hand its glide to the canvas.
@MainActor
struct ScrollLatchWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport.
    let viewportSpot = Point(x: Pixels(700), y: Pixels(300))

    func scroll(_ app: AppWindow, at point: Point<Pixels>, dy: Float = 20, modifiers: Modifiers = [],
                phase: InputPhase = .none, momentum: InputPhase = .none) {
        _ = app.window.send(.scrollWheel(ScrollEvent(
            position: point, delta: Point(x: Pixels(0), y: Pixels(dy)), modifiers: modifiers, phase: phase,
            momentumPhase: momentum, isPrecise: true, timestamp: app.window.now)))
        app.window.tick()
    }

    @Test func aGlideThatPansTheCanvasStaysOnItWhenThePointerDriftsOntoTheViewport() async throws {
        let app = try await AppWindow.open()
        let canvas = app.point(inCanvasView: Vector2(600, 100))
        let pose = app.model.viewport.pose
        app.window.hover(at: canvas)
        scroll(app, at: canvas, phase: .began)
        scroll(app, at: canvas, phase: .changed)
        scroll(app, at: canvas, dy: 0, phase: .ended)
        var offset = app.editor.transform.offset
        scroll(app, at: canvas, momentum: .began)
        #expect(app.editor.transform.offset != offset, "the glide pans the canvas")
        for _ in 0..<3 {
            offset = app.editor.transform.offset
            scroll(app, at: viewportSpot, momentum: .changed)
            #expect(app.editor.transform.offset != offset, "and goes on panning it with the pointer over the viewport")
        }
        scroll(app, at: viewportSpot, dy: 0, momentum: .ended)
        #expect(app.model.viewport.pose == pose, "the viewport never saw it")
    }

    @Test func aViewportZoomsGlideDoesNotReachTheCanvasWhenThePointerDriftsOntoIt() async throws {
        let app = try await AppWindow.open()
        let canvas = app.point(inCanvasView: Vector2(600, 100))
        app.window.hover(at: viewportSpot)
        scroll(app, at: viewportSpot, phase: .began)
        scroll(app, at: viewportSpot, phase: .changed)
        scroll(app, at: viewportSpot, dy: 0, phase: .ended)
        let transform = app.editor.transform
        scroll(app, at: canvas, momentum: .began)
        scroll(app, at: canvas, momentum: .changed)
        scroll(app, at: canvas, dy: 0, momentum: .ended)
        #expect(app.editor.transform == transform, "the glide began on the viewport, which ignores it, and ends there")
    }

    /// The glide's end releases the latch: the next wheel step, with no phase, goes to what is under the pointer.
    @Test func aWheelStepAfterAGlideGoesToWhatIsUnderThePointer() async throws {
        let app = try await AppWindow.open()
        let canvas = app.point(inCanvasView: Vector2(600, 100))
        app.window.hover(at: canvas)
        scroll(app, at: canvas, phase: .began)
        scroll(app, at: canvas, dy: 0, phase: .ended)
        scroll(app, at: canvas, momentum: .began)
        scroll(app, at: canvas, dy: 0, momentum: .ended)
        let transform = app.editor.transform
        let pose = app.model.viewport.pose
        scroll(app, at: viewportSpot, dy: 10)
        #expect(app.editor.transform == transform, "the latch is over")
        #expect(app.model.viewport.pose != pose, "a wheel step over the viewport zooms it")
    }

    /// Review Focus 5: key loss in the middle of a ⌘-scroll's glide leaves no stuck "ignore the glide" state, so the next
    /// glide pans.
    @Test func keyLossDuringAZoomsGlideLeavesNothingIgnoredForTheNextScroll() async throws {
        let app = try await AppWindow.open()
        let canvas = app.point(inCanvasView: Vector2(600, 100))
        app.window.hover(at: canvas)
        scroll(app, at: canvas, modifiers: .primary, phase: .began)
        scroll(app, at: canvas, dy: 0, modifiers: .primary, phase: .ended)
        scroll(app, at: canvas, modifiers: .primary, momentum: .began)
        #expect(app.editor.scrollGlideIgnored, "a zoom's glide is ignored")
        app.window.setControlActiveState(.inactive)
        #expect(!app.editor.scrollGlideIgnored, "the synthesized end of the glide releases it")
        app.window.setControlActiveState(.key)
        let offset = app.editor.transform.offset
        scroll(app, at: canvas, phase: .began)
        scroll(app, at: canvas, phase: .changed)
        #expect(app.editor.transform.offset != offset, "the next scroll pans")
    }
}
