import CreatorStyle
import MetalUI
import Testing

/// MetalUI's control tokens follow the theme, role by role, so its controls match the panels.
struct ControlThemeTests {
    @Test func draculasControlsUseItsRoles() {
        let tokens = ColorTheme.dracula.controlTheme
        #expect(tokens.background == .rgb(0x191a21))
        #expect(tokens.surface == .rgb(0x343746))
        #expect(tokens.surfaceSecondary == .rgb(0x44475a))
        #expect(tokens.accent == .rgb(0xbd93f9))
        #expect(tokens.separator == .rgb(0x6272a4))
        #expect(tokens.textPrimary == .rgb(0xf8f8f2))
        #expect(tokens.scrollIndicator == .rgb(0xf8f8f2, alpha: 0.35))
        #expect(tokens.scrim == Theme.dark.scrim && tokens.shadow == Theme.dark.shadow)
    }

    @Test func aLightThemeKeepsMetalUIsLightScrim() {
        #expect(ColorTheme.alucard.controlTheme.scrim == Theme.light.scrim)
        #expect(ColorTheme.alucard.controlTheme.accent == .rgb(0x644ac9))
    }

    /// A colour well is a `surface` bezel with a `separator` border around a track-coloured field: in every built-in
    /// the three differ, so none disappears into another.
    @Test(arguments: ColorTheme.builtIns)
    func everyBuiltInKeepsItsControlPartsApart(_ theme: ColorTheme) {
        let tokens = theme.controlTheme
        #expect(Set([tokens.surface, tokens.surfaceSecondary, tokens.separator, tokens.background]).count == 4)
    }

    @Test func aCustomThemesEditsReachTheControls() {
        var theme = ColorTheme.nord
        theme.colors.accent = HexColor(0x00ffaa)
        #expect(theme.controlTheme.accent == .rgb(0x00ffaa))
        #expect(HexColor(0x123456, opacity: 0.5).hsla == .rgb(0x123456, alpha: 0.5))
    }
}
