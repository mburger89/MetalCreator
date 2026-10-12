import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The idle editor's frames, counted by work and never by time (gap M7-b; MetalUI's `FrameWork`): a window is one
/// `Window` for its life, so every frame after the first is warm, with its shaping, rasters and textures kept. These pin
/// what must stay true of a warm frame whatever the machine: an idle window draws nothing, and a warm frame uploads no
/// glyph pixels, rasterizes and blurs no pixels and makes no texture. They are not timing assertions, and the release
/// benchmark (`Bench`, docs/verification/performance.md) stays the place for milliseconds.
@MainActor
struct WarmFrameTests {
    /// The editor with a small graph and a note on screen, laid out as production lays out (`recordsLayout: false`).
    func idleEditor() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box(at: Vector2(40, 40))
        var graph = builder.graph
        let note = TypingFixture().otherNote
        graph.stickies[note.id] = note
        let app = try await AppWindow.open(graph, recordsLayout: false)
        try await app.window.runUntilIdle()
        return app
    }

    @Test func theFirstFrameDoesTheColdWork() async throws {
        let app = try await idleEditor()
        let first = try #require(app.window.frameWork.first)
        #expect(first.atlasUploadPixels > 0, "the glyph atlas was filled")
        #expect(first.glyphs > 0 && first.rects > 0)
    }

    @Test func anIdleWindowDrawsNoFrameAtAll() async throws {
        let app = try await idleEditor()
        let drawn = app.window.framesDrawn
        let recorded = app.window.frameWork.count
        app.window.advanceFrames(10)
        try await app.window.runUntilIdle()
        #expect(app.window.framesDrawn == drawn, "ten display-link ticks with nothing dirty draw nothing")
        #expect(app.window.frameWork.count == recorded)
    }

    @Test func aWarmFrameUploadsRasterizesAndBlursNothing() async throws {
        let app = try await idleEditor()
        app.window.resetFrameWork()
        app.redraw()
        app.redraw()
        let warm = app.window.frameWork
        #expect(warm.count == 2)
        for work in warm {
            #expect(work.builds == 1)
            #expect(work.atlasUploadPixels == 0, "no glyph is shaped into the atlas again")
            #expect(work.rasterizedPixels == 0 && work.blurredPixels == 0, "no shadow or image is rasterized again")
            #expect(work.newTextures == 0 && work.newTexturePixels == 0)
        }
    }

    @Test func aSecondUnchangedFrameDoesExactlyTheWorkOfTheFirst() async throws {
        let app = try await idleEditor()
        app.window.resetFrameWork()
        app.redraw()
        app.redraw()
        let warm = app.window.frameWork
        #expect(warm.count == 2)
        #expect(warm[0] == warm[1], "a warm frame is steady: the same builds, measures, rects and glyphs every time")
    }
}
