import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct DimensionNumberTests {
    static func format(
        _ length: LengthUnit = .millimetres, _ standard: DrawingStandard = .iso, precision: Int? = nil, sign: DecimalSign = .point
    ) -> NumberFormat {
        NumberFormat(units: DocumentUnits(length: length, precision: precision), standard: standard, decimalSign: sign)
    }

    @Test func millimetresDropTrailingZeros() {
        #expect(DimensionNumber.length(25.0, precision: 2, format: Self.format()) == "25")
        #expect(DimensionNumber.length(25.40, precision: 2, format: Self.format()) == "25.4")
    }

    @Test func inchesKeepThem() {
        #expect(DimensionNumber.length(25.4, precision: 3, format: Self.format(.inches)) == "1.000")
    }

    @Test func asmeInchesDropTheLeadingZero() {
        #expect(DimensionNumber.length(6.35, precision: 3, format: Self.format(.inches, .asme)) == ".250")
        #expect(DimensionNumber.length(6.35, precision: 3, format: Self.format(.inches, .iso)) == "0.250")
        #expect(DimensionNumber.length(0.25, precision: 2, format: Self.format(.millimetres, .asme)) == "0.25")
    }

    @Test func aCommaInISO() {
        #expect(DimensionNumber.length(25.4, precision: 1, format: Self.format(sign: .comma)) == "25,4")
    }

    @Test func asmeIgnoresTheComma() {
        #expect(DimensionNumber.length(25.4, precision: 1, format: Self.format(.millimetres, .asme, sign: .comma)) == "25.4")
    }

    @Test func roundsHalfAwayFromZero() {
        #expect(DimensionNumber.length(0.125, precision: 2, format: Self.format()) == "0.13")
        #expect(DimensionNumber.length(-0.125, precision: 2, format: Self.format()) == "-0.13")
    }

    @Test func neverMinusZero() {
        #expect(DimensionNumber.length(-0.001, precision: 1, format: Self.format()) == "0")
        #expect(DimensionNumber.length(-0.0, precision: 2, format: Self.format(.inches)) == "0.00")
        #expect(DimensionNumber.angle(-0.0001, precision: 0, format: Self.format()) == "0°")
    }

    @Test func theMinusIsAscii() {
        let texts = [
            DimensionNumber.length(-3.5, precision: 1, format: Self.format()),
            DimensionNumber.angle(-1, precision: 1, format: Self.format()),
            DimensionNumber.signed(-0.2, places: 1, format: Self.format()),
        ]
        for text in texts { #expect(!text.unicodeScalars.contains { $0.value == 0x2212 }) }
        #expect(texts[0] == "-3.5")
    }

    @Test func anglesInDegrees() {
        let format = Self.format()
        #expect(DimensionNumber.angle(.pi / 6, precision: nil, format: format) == "30°")
        #expect(DimensionNumber.angle(0.5236, precision: 0, format: format) == "30°")
        #expect(DimensionNumber.angle(30.25 * .pi / 180, precision: 1, format: format) == "30.3°")
    }

    @Test func precisionOverridesTheDocument() {
        let format = Self.format(.inches, precision: 2)
        #expect(DimensionNumber.length(25.4, precision: 1, format: format) == "1.0")
        #expect(DimensionNumber.length(25.4, precision: nil, format: format) == "1.00")
    }

    @Test func deviationForms() {
        #expect(DimensionNumber.signed(0.1, places: 1, format: Self.format()) == "+0.1")
        #expect(DimensionNumber.signed(0, places: 1, format: Self.format()) == "0")
        let inches = Self.format(.inches, .asme)
        #expect(DimensionNumber.signed(0, places: 3, format: inches) == "+.000")
        #expect(DimensionNumber.signed(-0.0, places: 3, format: inches) == "-.000")
        #expect(DimensionNumber.places(of: "+.000") == 3)
        #expect(DimensionNumber.places(of: "25") == 0)
    }
}
