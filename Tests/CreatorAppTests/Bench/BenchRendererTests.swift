import Testing
@testable import CreatorApp

/// The benchmarks' renderer draws what the app draws. Runs in the default test run (a debug build, timing nothing), so
/// the harness can't rot between benchmark runs.
@MainActor
struct BenchRendererTests {
    @Test func itDrawsTheWindowAndTheViewport() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        let renderer = try BenchRenderer()
        renderer.place(app)
        #expect(app.panelPlacement != nil, "placed: the graph panel knows where it is")
        let scene = renderer.windowScene(app, input: AppInput(model: app))
        #expect(!scene.isEmpty)
        #expect(scene.surfaces.count == 1, "the viewport's surface is in the window")
        let drawn = renderer.viewportPasses
        try renderer.drawViewport(app.viewport)
        try renderer.composite(scene)
        #expect(renderer.viewportPasses == drawn + 1, "the viewport drew a frame")
    }
}
