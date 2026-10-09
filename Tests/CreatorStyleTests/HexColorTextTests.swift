import CreatorStyle
import MetalUI
import Testing

/// A colour as `.mctheme` text: `#rrggbb`, or `#rrggbbaa` when it is translucent, and back.
struct HexColorTextTests {
    @Test func itReadsSixAndEightDigitHex() {
        #expect(HexColor(hex: "#ff79c6") == HexColor(0xff79c6))
        #expect(HexColor(hex: "FF79C6") == HexColor(0xff79c6), "the # is optional and either case is read")
        #expect(HexColor(hex: " #50fa7b\n") == HexColor(0x50fa7b), "surrounding spaces are ignored")
        #expect(HexColor(hex: "#21222cdb") == HexColor(0x21222c, opacity: 219.0 / 255))
        #expect(HexColor(hex: "#00000000") == HexColor(0x000000, opacity: 0))
    }

    static let notColours = [
        "", "#", "pink", "ff79c", "#ff79c6f", "#ff79c6ff00", "#gg79c6", "+f79c6", "-f79c6", "#ff 79c6", "##ff79c6",
        "0xff79c6", "#ｆｆ79c6",
    ]

    @Test(arguments: notColours)
    func anythingElseIsNotAColour(_ text: String) {
        #expect(HexColor(hex: text) == nil)
    }

    @Test func itWritesLowercaseWithAlphaOnlyWhenTranslucent() {
        #expect(HexColor(0xff79c6).hex == "#ff79c6")
        #expect(HexColor(0x00000a).hex == "#00000a", "zero-padded")
        #expect(HexColor(0xffffff, opacity: 31.0 / 255).hex == "#ffffff1f")
        #expect(ColorTheme.dracula.colors.glassFill.hex == "#21222cdb", "86% is the nearest byte, 219")
        #expect(HexColor(0x123456, opacity: 0.999).hex == "#123456", "rounds to opaque")
    }

    static let samples = [
        HexColor(0xff79c6), HexColor(0x000000, opacity: 0), HexColor(0x21222c, opacity: 0.86),
        HexColor(0xf8f8f2, opacity: 0.9), HexColor(0xffffff, opacity: 31.0 / 255),
    ]

    @Test(arguments: samples)
    func textRoundTripsTheQuantizedColour(_ colour: HexColor) {
        #expect(HexColor(hex: colour.hex) == colour.quantized)
        #expect(colour.quantized.quantized == colour.quantized)
    }

    @Test func quantizingRoundsOnlyTheOpacity() {
        #expect(HexColor(0x21222c, opacity: 0.86).quantized == HexColor(0x21222c, opacity: 219.0 / 255))
        #expect(HexColor(0xff79c6).quantized == HexColor(0xff79c6))
    }

    /// `ColorPicker` writes gamma-sRGB literals; each channel comes back as its nearest byte.
    @Test func aMetalUIColourBecomesItsNearestBytes() {
        #expect(HexColor(Color(.sRGB, red: 1, green: 128.0 / 255, blue: 0, opacity: 0.5)) == HexColor(0xff8000, opacity: 128.0 / 255))
        #expect(HexColor(HexColor(0xbd93f9).color) == HexColor(0xbd93f9))
        #expect(HexColor(Color(.sRGB, red: 1.4, green: -0.2, blue: 0.5)) == HexColor(0xff0080), "clamped, then rounded")
    }
}
