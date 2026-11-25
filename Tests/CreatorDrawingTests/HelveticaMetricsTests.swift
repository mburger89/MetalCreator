import Testing

@testable import CreatorDrawing

@Suite("Helvetica metrics")
struct HelveticaMetricsTests {
    private func advance(_ c: Character) -> Int? {
        HelveticaMetrics.winAnsi(c).map { HelveticaMetrics.advance(of: $0) }
    }

    @Test func pinnedAdvances() {
        let pinned: [(Character, Int)] = [
            (" ", 278), ("A", 667), ("H", 722), ("W", 944), ("a", 556), ("i", 222), ("m", 833), (".", 278), ("°", 400),
            ("±", 584), ("×", 584), ("Ø", 778), ("µ", 556), ("…", 1000),
        ]
        for (character, width) in pinned { #expect(advance(character) == width, "\(character)") }
        for digit in "0123456789" { #expect(advance(digit) == 556) }
    }

    @Test func winAnsiMapsTheDrawingSymbols() {
        let expected: [(Character, UInt8)] = [
            ("Ø", 0xD8), ("±", 0xB1), ("°", 0xB0), ("×", 0xD7), ("µ", 0xB5), ("…", 0x85), ("€", 0x80),
        ]
        for (character, byte) in expected { #expect(HelveticaMetrics.winAnsi(character) == byte, "\(character)") }
    }

    @Test func outsideWinAnsiIsNil() {
        for character: Character in ["Ω", "→", "😀"] { #expect(HelveticaMetrics.winAnsi(character) == nil) }
    }

    @Test func theCapHeightIs718() {
        #expect(HelveticaMetrics.capHeight == 718)
    }
}
