import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// What fills the viewport's place in the window (cross-platform spec 2.3): the Metal 3D view on macOS and, where there is none,
/// a card saying so. The layout, top bar and panels around it are the same.
@MainActor
struct ViewportPaneTests {
    @Test func theCardSaysWhatTheSpecSays() {
        #expect(ViewportPlaceholder.message == "The 3D view isn't available on this platform yet.")
    }

    @Test func theWindowShowsTheCardExactlyWhereThereIsNoMetalView() async throws {
        let app = try await AppWindow.open()
        let cards = try app.window.elements { $0.label == ViewportPlaceholder.message || $0.value == ViewportPlaceholder.message }
        #if canImport(Metal)
        #expect(cards.isEmpty, "macOS draws the viewport")
        #else
        #expect(cards.count == 1, "the card stands in the viewport's place")
        #endif
        #expect(!app.window.scene.glyphs.isEmpty, "the top bar and panels draw whatever fills the viewport")
    }

    /// Sketch mode needs the viewport to draw on, which is xp-3's, but opening it must not trap and leaving it must work.
    @Test func aSketchStillOpensAndClosesWithTheCardWhereTheViewportIs() async throws {
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
