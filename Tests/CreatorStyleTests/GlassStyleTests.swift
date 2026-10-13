import CreatorStyle
import MetalUI
import Testing

/// The glass model (spec §6.1, §6.6): what a surface is built on, and how the theme's tint combines with a material.
@MainActor
struct GlassStyleTests {
    @Test(arguments: GlassThickness.allCases, [true, false])
    func theMaterialAndTheTintTogetherHideAsMuchAsTheThemesGlassDid(_ thickness: GlassThickness, _ isDark: Bool) {
        let material = thickness.materialOpacity(isDark: isDark)
        let tint = GlassStyle.tintOpacity(glass: 0.86, materialOpacity: material)
        if tint > 0 {
            #expect(abs((1 - tint) * (1 - material) - 0.14) < 1e-9, "\(thickness) \(isDark): the backdrop left over")
        } else {
            #expect(material >= 0.86, "no tint is only for a material already as opaque as the glass")
        }
    }

    @Test func draculaGlassOverTheThinnestMaterialIsA72PercentTintOfItsOwnColour() {
        let style = GlassStyle(theme: .dracula, surface: .topBar)
        #expect(style.thickness == .ultraThin)
        #expect(style.tint.rgb == 0x21222c, "the colour is the theme's, whatever the material")
        #expect(abs(style.tint.opacity - 0.7167) < 0.001, "86% less the material's 50.59%: \(style.tint.opacity)")
    }

    @Test func aThickerMaterialLeavesLessForTheTintAndAnOpaqueGlassStaysOpaque() {
        for isDark in [true, false] {
            let tints = GlassThickness.allCases.map {
                GlassStyle.tintOpacity(glass: 0.86, materialOpacity: $0.materialOpacity(isDark: isDark))
            }
            #expect(tints == tints.sorted(by: >), "\(isDark): \(tints)")
            for thickness in GlassThickness.allCases {
                #expect(GlassStyle.tintOpacity(glass: 1, materialOpacity: thickness.materialOpacity(isDark: isDark)) == 1)
                #expect(GlassStyle.tintOpacity(glass: 0, materialOpacity: thickness.materialOpacity(isDark: isDark)) == 0)
            }
        }
    }

    @Test func aMoreOpaqueGlassNeverGetsAThinnerTint() {
        for thickness in GlassThickness.allCases {
            let tints = stride(from: 0.0, through: 1.0, by: 0.05).map {
                GlassStyle.tintOpacity(glass: $0, materialOpacity: thickness.materialOpacity(isDark: true))
            }
            #expect(tints == tints.sorted(), "\(thickness): \(tints)")
            #expect(tints.allSatisfy { (0...1).contains($0) })
        }
    }

    @Test func aMaterialThatIsFullyOpaqueGetsNoTintAndNothingDividesByZero() {
        #expect(GlassStyle.tintOpacity(glass: 0.9, materialOpacity: 1) == 0)
    }

    @Test func reducingTransparencyMakesTheThemesColourOpaque() {
        let style = GlassStyle(theme: .dracula, surface: .graphPanel, reducesTransparency: true)
        #expect(style.tint == HexColor(0x21222c, opacity: 1))
        #expect(GlassStyle(theme: .dracula, surface: .graphPanel).tint.opacity < 1)
    }

    @Test(arguments: ColorTheme.builtIns, GlassSurface.allCases)
    func reducingTransparencyKeepsEveryThemesTextLegible(_ theme: ColorTheme, _ surface: GlassSurface) {
        let tint = GlassStyle(theme: theme, surface: surface, reducesTransparency: true).tint
        #expect(tint.opacity == 1 && tint.rgb == theme.colors.glassFill.rgb, "the theme's own colour, opaque")
        #expect(ThemeTests.contrast(theme.colors.foreground, tint) >= 7, "\(theme.name) \(surface): primary text")
        #expect(ThemeTests.contrast(theme.colors.comment, tint) >= 3, "\(theme.name) \(surface): dim text")
    }

    @Test func theStyleFollowsTheThemesColourAndItsLightOrDark() {
        let dracula = GlassStyle(theme: .dracula, surface: .inspector)
        let alucard = GlassStyle(theme: .alucard, surface: .inspector)
        #expect(dracula.colorScheme == .dark && alucard.colorScheme == .light)
        #expect(dracula.tint.rgb == ColorTheme.dracula.colors.glassFill.rgb)
        #expect(alucard.tint.rgb == ColorTheme.alucard.colors.glassFill.rgb)
        #expect(dracula.tint != alucard.tint)
    }

    @Test func aThemeEditorEditOfTheGlassOpacityReachesTheTint() {
        var theme = ColorTheme.dracula
        theme.colors.glassFill = HexColor(0x21222c, opacity: 0.5)
        let style = GlassStyle(theme: theme, surface: .topBar)
        #expect(style.tint.opacity < GlassStyle(theme: .dracula, surface: .topBar).tint.opacity)
    }

    @Test func eachSurfaceHasTheThicknessTheDecisionGaveIt() {
        let thicknesses = Dictionary(uniqueKeysWithValues: GlassSurface.allCases.map { ($0, $0.thickness) })
        #expect(thicknesses == [
            .graphPanel: .ultraThin, .inspector: .ultraThin, .topBar: .ultraThin, .pickBanner: .ultraThin,
            .showButton: .ultraThin, .palette: .thin, .themeEditor: .ultraThin, .chip: .ultraThin, .fieldLegend: .ultraThin,
        ])
    }

    @Test func aStoreSupplyingTheThemeIsReadAndNoStoreIsDracula() {
        let store = ThemeStore()
        store.select("alucard")
        #expect(GlassStyle(themes: store, surface: .topBar) == GlassStyle(theme: .alucard, surface: .topBar))
        #expect(GlassStyle(themes: nil, surface: .topBar) == GlassStyle(theme: .dracula, surface: .topBar))
    }
}
