import CreatorGeometry
import CreatorStyle
import CreatorViewport
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorSketchEditor

/// Reduce Transparency through real headless windows (MetalUI C27, gap C21-b): `HeadlessPlatformWindow.Options` starts a
/// window with the setting on and `TestWindow.setReduceTransparency(_:)` flips it while the window runs. With it on,
/// MetalUI draws every material as an opaque grey rect and never a backdrop record (divergence 315), each glass panel
/// lays the theme's glass colour over it at full opacity (`GlassStyle.tint`), and the text is still drawn; with it off the
/// frame is the C21 frame. The panels are counted by the backdrop records of the setting-off frame, not by a number written
/// here, so a new default panel needs no edit. How the grey and the opaque colour look in a real window is human check C21-5.
@MainActor
struct GlassReduceTransparencyWindowTests {
    static let reducing = HeadlessPlatformWindow.Options(accessibilityReduceTransparency: true)

    func hsla(_ colour: HexColor) -> [Float] {
        let value = colour.hsla
        return [value.h, value.s, value.l, value.a]
    }

    func isClose(_ a: [Float], _ b: [Float]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.01 } }

    /// Every rect's background, so two frames compare without `MUIRect` being `Equatable`.
    func backgrounds(_ scene: Scene) -> [[Float]] {
        scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
    }

    /// How many rects of the scene are filled with `colour`.
    func count(_ scene: Scene, _ colour: HexColor) -> Int {
        backgrounds(scene).filter { isClose($0, hsla(colour)) }.count
    }

    @Test func withTheSettingOnNoPanelOfTheAppBlurs() async throws {
        let on = try await AppWindow.open(options: Self.reducing).window.scene
        let off = try await AppWindow.open().window.scene
        #expect(on.backdrops.isEmpty, "MetalUI draws a material as a plain rect, never a backdrop record")
        #expect(!off.backdrops.isEmpty, "with the setting off the panels blur as before")
    }

    @Test func withTheSettingOnEveryPanelIsTheThemesGlassColourAtFullOpacity() async throws {
        let on = try await AppWindow.open(options: Self.reducing).window.scene
        let off = try await AppWindow.open().window.scene
        let opaque = GlassStyle(theme: .dracula, surface: .graphPanel, reducesTransparency: true).tint
        let translucent = GlassStyle(theme: .dracula, surface: .graphPanel).tint
        #expect(opaque.opacity == 1)
        // One tint rect per glass surface drawn, and a surface is a backdrop record when it blurs.
        #expect(count(on, opaque) == off.backdrops.count, "each panel's glass is the theme's colour, opaque")
        #expect(count(on, translucent) == 0, "the see-through tint is gone: nothing is left to see through it")
    }

    @Test func withTheSettingOnTheTextIsStillDrawnAndNothingIsDropped() async throws {
        let on = try await AppWindow.open(options: Self.reducing).window.scene
        let off = try await AppWindow.open().window.scene
        #expect(!on.glyphs.isEmpty)
        #expect(on.glyphs.count == off.glyphs.count, "every label is drawn with the setting on, as with it off")
    }

    @Test func withTheSettingOffTheFrameIsTheBlurringOne() async throws {
        let off = try await AppWindow.open(options: .init(accessibilityReduceTransparency: false)).window.scene
        let style = GlassStyle(theme: .dracula, surface: .graphPanel)
        #expect(!off.backdrops.isEmpty)
        #expect(count(off, style.tint) > 0, "the tint is the derived see-through one")
        #expect(off.backdrops.allSatisfy { abs(Double($0.tint.a) - style.thickness.materialOpacity(isDark: true)) < 1e-4 })
    }

    @Test func theSettingFollowsTheSystemWhileTheAppRunsInBothDirections() async throws {
        let app = try await AppWindow.open()
        let before = backgrounds(app.window.scene)
        let panels = app.window.scene.backdrops.count
        #expect(panels > 0)
        app.window.setReduceTransparency(true)
        let opaque = GlassStyle(theme: .dracula, surface: .graphPanel, reducesTransparency: true).tint
        #expect(app.window.scene.backdrops.isEmpty)
        #expect(count(app.window.scene, opaque) == panels)
        #expect(backgrounds(app.window.scene) != before)
        app.window.setReduceTransparency(false)
        #expect(app.window.scene.backdrops.count == panels)
        #expect(backgrounds(app.window.scene) == before, "switched back off, the frame is the original one")
    }

    @Test func thePaletteIsOpaqueToo() async throws {
        let app = try await AppWindow.open(options: Self.reducing)
        app.window.hover(at: app.point(inCanvasView: Vector2(200, 40)))
        app.window.typeKey(.space)
        try await app.window.runUntilIdle()
        #expect(app.palettePanel != nil, "the palette opened")
        #expect(app.window.scene.backdrops.isEmpty)
        let palette = GlassStyle(theme: .dracula, surface: .palette, reducesTransparency: true).tint
        #expect(count(app.window.scene, palette) > 0)
    }

    func chipScene(_ options: HeadlessPlatformWindow.Options) throws -> Scene {
        let chip = try #require(ReadoutChip(text: "12.5 mm", pointer: ScreenPoint(300, 200),
                                            in: ViewportSize(width: 700, height: 500), measuring: .fake))
        let window = try TestWindow(options: options) {
            ZStack(alignment: .topLeading) { ReadoutChipView(chip: chip) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        return window.scene
    }

    @Test func theSketchChipsFollowTheSettingToo() throws {
        let on = try chipScene(Self.reducing)
        let off = try chipScene(.init())
        #expect(on.backdrops.isEmpty && off.backdrops.count == 1)
        #expect(count(on, GlassStyle(theme: .dracula, surface: .chip, reducesTransparency: true).tint) == 1)
        #expect(!on.glyphs.isEmpty && on.glyphs.count == off.glyphs.count)
    }
}
