import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// What fills the viewport's place in the window (cross-platform spec section 4): the real 3D view on every platform, drawn by Metal
/// on macOS and by SDL_GPU on Linux and Windows. The layout, top bar and panels around it are the same.
@MainActor
struct ViewportPaneTests {
    @Test func theWindowHasTheViewportsGPUSurfaceWhereverItRuns() async throws {
        let app = try await AppWindow.open()
        #expect(app.window.scene.surfaces.count == 1, "the viewport's GPU surface fills its place, on every platform")
        #expect(!app.window.scene.glyphs.isEmpty, "the top bar and panels draw around it")
    }

    /// Sketch mode needs the viewport to draw on; opening it must not trap and leaving it must work.
    @Test func aSketchOpensAndClosesWithTheViewportWhereItIs() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = try await AppWindow.open(builder.graph)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        #expect(app.model.sketch != nil)
        app.model.finishSketch()
        #expect(app.model.sketch == nil)
    }
}
