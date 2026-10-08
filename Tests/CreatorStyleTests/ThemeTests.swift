import CreatorStyle
import Foundation
import MetalUI
import Testing

/// The built-in themes (spec §6.6: themeable, Dracula by default) and `HexColor`.
struct ThemeTests {
    /// Every opaque Dracula role and its hex value in the spec §6.6 table (and the sketcher spec's §8).
    static let dracula: [(HexColor, UInt32)] = {
        let c = ColorTheme.dracula.colors
        return [
            (c.backgroundTop, 0x3a3d4e), (c.backgroundBottom, 0x191a21), (c.panelBase, 0x282a36), (c.nodeBody, 0x343746),
            (c.field, 0x44475a), (c.foreground, 0xf8f8f2), (c.comment, 0x6272a4), (c.textOnAccent, 0x282a36),
            (c.accent, 0xbd93f9), (c.focus, 0x8be9fd), (c.selection, 0xff79c6), (c.valueHeader, 0x6272a4),
            (c.profileHeader, 0x50fa7b), (c.solidHeader, 0xbd93f9), (c.selectionHeader, 0xff79c6),
            (c.featureHeader, 0xffb86c), (c.outputHeader, 0x8be9fd), (c.success, 0x50fa7b), (c.warning, 0xf1fa8c),
            (c.error, 0xff5555), (c.shadeLight, 0xc5c8de), (c.shadeDark, 0x6f739a), (c.gridMinor, 0x44475a),
            (c.gridMajor, 0x6272a4), (c.cubeFace, 0x44475a), (c.cubeRim, 0x343746), (c.cubeLabel, 0xf8f8f2),
            (c.axisX, 0xff5555), (c.axisY, 0x50fa7b), (c.axisZ, 0x8be9fd), (c.sketchUnderConstrained, 0x8be9fd),
            (c.sketchFullyConstrained, 0xf8f8f2), (c.sketchConflicting, 0xff5555), (c.sketchConstruction, 0x6272a4),
            (c.sketchProjected, 0xbd93f9),
        ]
    }()

    @Test(arguments: dracula)
    func draculaFollowsTheSpecTable(_ colour: HexColor, _ rgb: UInt32) {
        #expect(colour == HexColor(rgb))
    }

    @Test func draculasTranslucentRolesHaveTheirOpacities() {
        #expect(ColorTheme.dracula.colors.glassFill == HexColor(0x21222c, opacity: 0.86))
        #expect(ColorTheme.dracula.colors.glassStroke == HexColor(0xffffff, opacity: 31.0 / 255))
        #expect(ColorTheme.dracula.colors.edge == HexColor(0xf8f8f2, opacity: 0.9))
    }

    /// Alucard is Dracula's official light variant, in its published colours (draculatheme.com/spec).
    @Test func alucardIsDraculasPublishedLightVariant() {
        let c = ColorTheme.alucard.colors
        #expect(!ColorTheme.alucard.isDark && ColorTheme.dracula.isDark && ColorTheme.nord.isDark)
        #expect(c.panelBase == HexColor(0xfffbeb) && c.foreground == HexColor(0x1f1f1f) && c.comment == HexColor(0x6c664b))
        #expect(c.field == HexColor(0xcfcfde), "Alucard's selection background")
        #expect([c.profileHeader, c.solidHeader, c.selection, c.featureHeader, c.focus, c.warning, c.error]
            == [0x14710a, 0x644ac9, 0xa3144d, 0xa34d14, 0x036a96, 0x846e15, 0xcb3a2a].map { HexColor($0) })
        #expect(c.textOnAccent == c.panelBase, "light text on Alucard's darker accents")
    }

    @Test func theBuiltInsAreDraculaFirstThenAlucardAndNord() {
        #expect(ColorTheme.builtIns.map(\.id) == ["dracula", "alucard", "nord"])
        #expect(ColorTheme.builtIns.map(\.name) == ["Dracula", "Alucard", "Nord"])
        #expect(Set(ColorTheme.builtIns.map(\.colors)).count == 3)
    }

    /// Every built-in can be read: text on panels and nodes, dim text, and the text on each node header
    /// (WCAG contrast; Dracula's own comment grey on its panel is 3.0:1, the floor).
    @Test(arguments: ColorTheme.builtIns)
    func everyBuiltInIsLegible(_ theme: ColorTheme) {
        let c = theme.colors
        #expect(Self.contrast(c.foreground, c.panelBase) >= 7 && Self.contrast(c.foreground, c.nodeBody) >= 7)
        #expect(Self.contrast(c.comment, c.panelBase) >= 3)
        for header in [c.valueHeader, c.profileHeader, c.solidHeader, c.selectionHeader, c.featureHeader, c.outputHeader] {
            #expect(Self.contrast(c.textOnAccent, header) >= 3, "\(theme.name): text on #\(String(header.rgb, radix: 16))")
        }
    }

    @Test func hexColourBecomesAnSRGBColour() {
        #expect(HexColor(0xff8000, opacity: 0.5).color == Color(red: 1, green: 128.0 / 255, blue: 0, opacity: 0.5))
    }

    @Test func hexColourBecomesGammaSpaceRGBA() {
        #expect(HexColor(0xff8000, opacity: 0.5).rgba == SIMD4<Float>(1, Float(128) / 255, 0, 0.5))
        #expect(HexColor(0x8be9fd).rgba == SIMD4<Float>(Float(0x8b) / 255, Float(0xe9) / 255, Float(0xfd) / 255, 1))
    }

    /// The WCAG 2 contrast ratio of two opaque colours.
    static func contrast(_ a: HexColor, _ b: HexColor) -> Double {
        func luminance(_ colour: HexColor) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let value = Double((colour.rgb >> UInt32(shift)) & 0xff) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }
}
