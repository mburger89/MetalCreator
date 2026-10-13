import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// A glass panel is the theme's own glass colour laid over a material that blurs the backdrop (gap C10-a, adopted with
/// MetalUI C21): the colour follows the theme and its role's opacity, the material is the surface's, and the two together
/// hide as much of the backdrop as the role says. The look over a moving viewport is human check C21-1.
@MainActor
struct GlassFillTests {
    func hsla(_ colour: HexColor) -> [Float] {
        let hsla = colour.hsla
        return [hsla.h, hsla.s, hsla.l, hsla.a]
    }

    func scene(_ store: ThemeStore?, _ surface: GlassSurface = .graphPanel) -> Scene {
        renderHeadless { GlassPanel(surface) { Text("Graph") }.environment(store) }
    }

    func fills(_ store: ThemeStore?, _ surface: GlassSurface = .graphPanel) -> [[Float]] {
        scene(store, surface).rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
    }

    func isClose(_ a: [Float], _ b: [Float]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.01 } }

    @Test func aPanelIsTheThemesGlassColourOverABlurringMaterial() throws {
        let style = GlassStyle(theme: .dracula, surface: .graphPanel)
        let scene = scene(nil)
        #expect(scene.backdrops.count == 1, "one material, behind the tint")
        #expect(fills(nil).contains { isClose($0, hsla(style.tint)) }, "the theme's colour is drawn")
        #expect(!fills(nil).contains { isClose($0, hsla(Palette.dracula.glass)) },
                "not at the role's opacity: the material under it hides part of the backdrop")
    }

    @Test func theTintAndTheMaterialHideWhatTheThemesGlassOpacitySays() throws {
        let scene = scene(nil)
        let backdrop = try #require(scene.backdrops.first)
        let tint = try #require(scene.rects.first { abs($0.background.a - 0.7167) < 0.01 })
        let hidden = 1 - Double(1 - tint.background.a) * Double(1 - backdrop.tint.a)
        #expect(abs(hidden - Palette.dracula.glass.opacity) < 0.01, "hides \(hidden) of the backdrop, the theme's glass is 0.86")
    }

    @Test func theGlassColourFollowsTheTheme() throws {
        let store = ThemeStore()
        store.select("alucard")
        let style = GlassStyle(theme: .alucard, surface: .graphPanel)
        #expect(fills(store).contains { isClose($0, hsla(style.tint)) })
        #expect(fills(store) != fills(nil))
        let backdrop = try #require(scene(store).backdrops.first)
        #expect(abs(Double(backdrop.tint.a) - GlassThickness.ultraThin.materialOpacity(isDark: false)) < 1e-4,
                "the light theme's material")
    }

    @Test func aGlassOpacityLoweredInTheThemeEditorLowersTheTint() {
        var colors = ColorTheme.dracula.colors
        colors.glassFill = HexColor(0x21222c, opacity: 0.4)
        let theme = ColorTheme(id: "lowered", name: "Lowered", isDark: true, colors: colors)
        let store = ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "lowered"), builtIns: [theme])
        #expect(store.current == theme)
        let style = GlassStyle(theme: theme, surface: .graphPanel)
        #expect(style.tint.opacity < GlassStyle(theme: .dracula, surface: .graphPanel).tint.opacity)
        #expect(fills(store).contains { isClose($0, hsla(style.tint)) })
        #expect(!fills(store).contains { isClose($0, hsla(GlassStyle(theme: .dracula, surface: .graphPanel).tint)) })
    }

    @Test(arguments: GlassSurface.allCases)
    func everySurfaceBlursWithItsOwnThickness(_ surface: GlassSurface) throws {
        let backdrop = try #require(scene(nil, surface).backdrops.first)
        #expect(abs(Double(backdrop.tint.a) - surface.thickness.materialOpacity(isDark: true)) < 1e-4)
    }

    @Test func aPanelHasNoImagesSoNothingIsRasterised() {
        // MetalUI draws a material as flat tint inside a shadow, a blur or a compositing group (its divergence 248), and
        // those rasterise to images; the panels use none of them.
        #expect(scene(nil).images.isEmpty)
    }
}
