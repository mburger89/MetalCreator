import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

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

    /// Gap M4-a: the viewport fills the window, and learns its size from its layout (`onGeometryChange`) rather than from
    /// a draw the headless platform does not run.
    @Test func theViewportLearnsTheWindowsSizeFromItsLayout() async throws {
        let app = try await AppWindow.open()
        #expect(app.model.viewport.viewSize == ViewportSize(width: app.size.x, height: app.size.y))
    }

    @Test func aResizedWindowResizesTheViewport() async throws {
        let app = try await AppWindow.open()
        app.window.resize(to: Size(width: Pixels(1100), height: Pixels(700)))
        #expect(app.model.viewport.viewSize == ViewportSize(width: 1100, height: 700))
    }

    /// New and Open build a fresh `ViewportModel` under the same view: it is told the size again at once.
    @Test func aDocumentLoadedIntoTheWindowLearnsTheSizeToo() async throws {
        let app = try await AppWindow.open()
        let first = app.model.viewport
        app.model.load(GraphFile(), from: nil)
        app.redraw()
        try #require(app.model.viewport !== first)
        #expect(app.model.viewport.viewSize == ViewportSize(width: app.size.x, height: app.size.y))
    }
}
