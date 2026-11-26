import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct GDTNumberTests {
    static func format(
        _ length: LengthUnit = .millimetres, _ standard: DrawingStandard = .iso, precision: Int? = nil, sign: DecimalSign = .point
    ) -> NumberFormat {
        NumberFormat(units: DocumentUnits(length: length, precision: precision), standard: standard, decimalSign: sign)
    }

    @Test func tolerancesTakeTheDecimalsTheyNeed() {
        let format = Self.format(precision: 1)
        #expect(GDTNumber.tolerance(0.05, format: format) == "0.05")
        #expect(GDTNumber.tolerance(0.1, format: format) == "0.1")
        #expect(GDTNumber.tolerance(0.12345, format: format) == "0.1235")
    }

    @Test func inchTolerancesKeepPrecision() {
        #expect(GDTNumber.tolerance(0.127, format: Self.format(.inches, .asme, precision: 3)) == ".005")
        #expect(GDTNumber.tolerance(0.127, format: Self.format(.inches, .iso, precision: 3)) == "0.005")
    }

    @Test func theCommaIsUsed() {
        #expect(GDTNumber.tolerance(0.05, format: Self.format(sign: .comma)) == "0,05")
    }

    @Test func roughnessInMillimetreDocuments() {
        let format = Self.format()
        #expect(GDTNumber.roughness(1.6, format: format) == "1.6")
        #expect(GDTNumber.roughness(0.8, format: format) == "0.8")
        #expect(GDTNumber.roughness(12.5, format: format) == "12.5")
    }

    @Test func roughnessInInchesIsMicroinches() {
        let format = Self.format(.inches)
        #expect(GDTNumber.roughness(1.6, format: format) == "63")
        #expect(GDTNumber.roughness(3.2, format: format) == "126")
        #expect(GDTNumber.roughness(0.8, format: format) == "31")
    }
}
