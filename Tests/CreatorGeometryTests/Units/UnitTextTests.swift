import Testing
@testable import CreatorGeometry

struct UnitTextTests {
    let mm = DocumentUnits()
    let inch = DocumentUnits(length: .inches)

    @Test func editTextKeepsEnoughDigitsToChangeNothing() {
        #expect(mm.editText(60, quantity: .length) == "60")
        #expect(mm.editText(12.345678, quantity: .length) == "12.3457")
        #expect(inch.editText(60, quantity: .length) == "2.3622")
        #expect(mm.editText(22.5, quantity: .angle) == "22.5")
        #expect(mm.editText(6, quantity: .count) == "6")
        #expect(mm.editText(-0.00001, quantity: .length) == "0")
    }

    @Test func fieldTextRoundsToThePrecisionWithItsSuffix() {
        #expect(mm.fieldText(12.5, quantity: .length) == "12.5 mm")
        #expect(mm.fieldText(60, quantity: .length) == "60 mm")
        #expect(inch.fieldText(57.15, quantity: .length) == "2.25 in")
        #expect(inch.fieldText(12.7, quantity: .length) == "0.50 in")
        #expect(mm.fieldText(30, quantity: .angle) == "30°")
        #expect(mm.fieldText(22.25, quantity: .angle) == "22.3°")
        #expect(mm.fieldText(6, quantity: .count) == "6")
    }

    @Test func suffixesNameTheUnit() {
        #expect(mm.suffix(for: .length) == " mm")
        #expect(mm.suffix(for: .radius) == " mm")
        #expect(inch.suffix(for: .diameter) == " in")
        #expect(mm.suffix(for: .angle) == "°")
        #expect(mm.suffix(for: .count) == "")
    }

    @Test func readoutNumbersAreFixedDigits() {
        #expect(mm.readoutNumber(24.5) == "24.5")
        #expect(mm.readoutNumber(24) == "24.0")
        #expect(mm.readoutNumber(-0.04) == "0.0")
        #expect(inch.readoutNumber(24.5) == "0.96")
    }
}
