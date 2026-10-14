import CreatorGeometry
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorApp

/// The add-node palette is an `anchoredOverlay`, drawn on its own layer over the whole window. Its glass blurs what is beneath
/// it, which includes the viewport and the graph panel's glass, so its material must be painted after both.
@MainActor
struct GlassPaletteWindowTests {
    #if canImport(Metal)
    @Test func thePalettesGlassBlursTheViewportAndTheGraphPanelBeneathIt() async throws {
        let app = try await AppWindow.open(dock: .bottom)
        app.window.hover(at: app.point(inCanvasView: Vector2(200, 40)))
        app.window.typeKey(.space)
        try await app.window.runUntilIdle()
        let glass = try #require(app.palettePanel).frame
        let panel = try #require(app.model.panelPlacement).panel
        let scene = app.window.scene
        func backdrop(at origin: Vector2) -> Int? {
            scene.backdrops.indices.first { (frame(of: scene.backdrops[$0].bounds, scale: 1).origin - origin).length < 0.5 }
        }
        let palette = try #require(backdrop(at: Vector2(Double(glass.origin.x.value), Double(glass.origin.y.value))),
                                   "the palette's glass is a material record where the overlay placed it")
        let graphPanel = try #require(backdrop(at: panel.origin), "so is the graph panel's")
        let surface = try #require(paintPosition(of: .surface, at: 0, in: scene))
        let paletteAt = try #require(paintPosition(of: .backdrop, at: palette, in: scene))
        let panelAt = try #require(paintPosition(of: .backdrop, at: graphPanel, in: scene))
        #expect(paletteAt > surface && paletteAt > panelAt, "painted after the viewport and after the panel it floats over")
        #expect(abs(Double(scene.backdrops[palette].tint.a) - GlassThickness.thin.materialOpacity(isDark: true)) < 1e-4,
                "the palette is one step thicker than the panels")
    }
    #endif
}
