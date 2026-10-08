import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

struct PaletteTests {
    @Test(arguments: [
        (NodeCategory.value, UInt32(0x6272a4)), (.profile, 0x50fa7b), (.solid, 0xbd93f9),
        (.selection, 0xff79c6), (.feature, 0xffb86c), (.output, 0x8be9fd),
    ])
    func headerColoursFollowTheSpecTable(_ category: NodeCategory, _ rgb: UInt32) {
        #expect(Palette.dracula.header(for: category) == HexColor(rgb))
    }

    @Test func selectionGlowIsTheNodesOwnHeaderColour() {
        for category in NodeCategory.allCases {
            #expect(Palette.dracula.selection(for: category) == Palette.dracula.header(for: category))
        }
    }

    @Test func textOnAccentsIsThePanelBase() {
        #expect(Palette.dracula.textOnAccent == HexColor(0x282a36))
    }

    @Test func socketsShareTheirCategoryColours() {
        #expect(Palette.dracula.socket(.profile) == Palette.dracula.header(for: .profile))
        #expect(Palette.dracula.socket(.solid) == Palette.dracula.header(for: .solid))
        #expect(Palette.dracula.socket(.edgeSet) == Palette.dracula.header(for: .selection))
        #expect(Palette.dracula.socket(.faceSet) == Palette.dracula.header(for: .selection))
        #expect(Palette.dracula.socket(.number) == Palette.dracula.header(for: .value))
    }

    @Test func glassAndHairlineHaveTheirOpacities() {
        #expect(Palette.dracula.glass == HexColor(0x21222c, opacity: 0.86))
        #expect(Palette.dracula.hairline == HexColor(0xffffff, opacity: 31.0 / 255))
    }

    @Test func statusColours() {
        #expect(Palette.dracula.status(.ok(duration: .milliseconds(3))) == HexColor(0x50fa7b))
        #expect(Palette.dracula.status(.warning("w")) == HexColor(0xf1fa8c))
        #expect(Palette.dracula.status(.error("e")) == HexColor(0xff5555))
    }

    /// Every role follows the theme: Alucard's headers, sockets, glass and status colours.
    @Test func aThemesPaletteNamesItsRoles() {
        let palette = Palette(.alucard)
        #expect(palette.header(for: .profile) == HexColor(0x14710a))
        #expect(palette.socket(.edgeSet) == HexColor(0xa3144d))
        #expect(palette.textOnAccent == HexColor(0xfffbeb))
        #expect(palette.glass == HexColor(0xefeddc, opacity: 0.86))
        #expect(palette.status(.error("e")) == HexColor(0xcb3a2a))
        #expect(palette.selection == HexColor(0xa3144d))
    }

    /// A view with no `ThemeStore` above it (a headless test, `GraphPanelPreview`) draws Dracula.
    @MainActor
    @Test func withoutAThemeStoreViewsDrawDracula() {
        #expect(Palette(nil as ThemeStore?) == .dracula)
        let store = ThemeStore()
        store.select("nord")
        #expect(Palette(store) == Palette(.nord))
    }
}
