import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// The glass panel keeps the theme's own translucent fill (gap M5-c): neither a MetalUI material, whose grey ignores the
/// theme, nor a blur. The look is human check C10-1.
@MainActor
struct GlassFillTests {
    func hsla(_ colour: HexColor) -> [Float] {
        let hsla = colour.hsla
        return [hsla.h, hsla.s, hsla.l, hsla.a]
    }

    func fills(_ store: ThemeStore?) -> [[Float]] {
        renderHeadless { GlassPanel { Text("Graph") }.environment(store) }
            .rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
    }

    @Test func aPanelIsFilledWithTheThemesGlassColourAtItsOwnOpacity() {
        let glass = Palette.dracula.glass
        #expect(glass.opacity == 0.86)
        #expect(fills(nil).contains { zip($0, hsla(glass)).allSatisfy { abs($0 - $1) < 0.01 } })
    }

    @Test func aPanelHasNoImagesSoNothingIsBlurredOrRasterised() {
        let scene = renderHeadless { GlassPanel { Text("Graph") } }
        #expect(scene.images.isEmpty)
    }

    @Test func theGlassColourFollowsTheTheme() {
        let store = ThemeStore()
        store.select("alucard")
        let glass = Palette(ColorTheme.alucard).glass
        #expect(fills(store).contains { zip($0, hsla(glass)).allSatisfy { abs($0 - $1) < 0.01 } })
        #expect(fills(store) != fills(nil))
    }
}
