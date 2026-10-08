import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

struct PaletteTests {
    @Test(arguments: [
        (NodeCategory.value, UInt32(0x6272a4)), (.profile, 0x50fa7b), (.solid, 0xbd93f9),
        (.selection, 0xff79c6), (.feature, 0xffb86c), (.output, 0x8be9fd),
    ])
    func headerColoursFollowTheSpecTable(_ category: NodeCategory, _ rgb: UInt32) {
        #expect(Palette.header(for: category) == HexColor(rgb))
    }

    @Test func selectionGlowIsTheNodesOwnHeaderColour() {
        for category in NodeCategory.allCases {
            #expect(Palette.selection(for: category) == Palette.header(for: category))
        }
    }

    @Test func textOnAccentsIsThePanelBase() {
        #expect(Palette.textOnAccent == HexColor(0x282a36))
    }

    @Test func socketsShareTheirCategoryColours() {
        #expect(Palette.socket(.profile) == Palette.header(for: .profile))
        #expect(Palette.socket(.solid) == Palette.header(for: .solid))
        #expect(Palette.socket(.edgeSet) == Palette.header(for: .selection))
        #expect(Palette.socket(.faceSet) == Palette.header(for: .selection))
        #expect(Palette.socket(.number) == Palette.header(for: .value))
    }

    @Test func glassAndHairlineHaveTheirOpacities() {
        #expect(Palette.glass == HexColor(0x21222c, opacity: 0.86))
        #expect(Palette.hairline == HexColor(0xffffff, opacity: 31.0 / 255))
    }

    @Test func statusColours() {
        #expect(Palette.status(.ok(duration: .milliseconds(3))) == HexColor(0x50fa7b))
        #expect(Palette.status(.warning("w")) == HexColor(0xf1fa8c))
        #expect(Palette.status(.error("e")) == HexColor(0xff5555))
    }

    @Test func hexColourBecomesAnSRGBColour() {
        #expect(HexColor(0xff8000, opacity: 0.5).color == Color(red: 1, green: 128.0 / 255, blue: 0, opacity: 0.5))
    }
}
