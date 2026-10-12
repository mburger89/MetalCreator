import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The app's real window over MetalUITesting's headless platform (`AppWindow`): it opens the app's own root with the
/// app's own menu bar, and its geometry helpers agree with where MetalUI routes the pointer.
@MainActor
struct AppWindowTests {
    @Test func theRealRootOpensWithTheAppsMenuBar() async throws {
        let app = try await AppWindow.open()
        #expect(app.window.title == "MetalCreator")
        let titles = app.testApp.menuBar.map(\.title)
        #expect(["File", "Edit", "View"].allSatisfy(titles.contains))
        #expect(app.window.framesDrawn >= 1)
    }

    @Test func aPointInTheCanvasReachesTheCanvasAtTheSamePlace() async throws {
        let app = try await AppWindow.open()
        #expect(app.canvasFrame.origin != .zero, "the canvas is placed inside the window")
        let local = Vector2(120, 80)
        app.window.hover(at: app.point(inCanvasView: local))
        #expect(app.editor.pointerLocation == local, "the canvas sees the pointer where the helper put it")
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.editor.pointerLocation == nil, "and sees it leave over the viewport")
    }
}
