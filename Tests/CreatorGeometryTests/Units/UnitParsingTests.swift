import Testing
@testable import CreatorGeometry

struct UnitParsingTests {
    let mm = DocumentUnits()
    let inch = DocumentUnits(length: .inches)

    @Test func readsTheDocumentsUnitOrASuffix() {
        #expect(mm.parse(" 12.5 mm ", quantity: .length) == 12.5)
        #expect(mm.parse("12.5MM", quantity: .length) == 12.5)
        #expect(mm.parse("2in", quantity: .length) == 50.8)
        #expect(mm.parse("2\"", quantity: .length) == 50.8)
        #expect(mm.parse("2 inches", quantity: .length) == 50.8)
        #expect(mm.parse("5 cm", quantity: .length) == 50)
        #expect(mm.parse(".5", quantity: .length) == 0.5)
        #expect(inch.parse("2", quantity: .length) == 50.8)
        #expect(inch.parse("50 mm", quantity: .length) == 50)
        #expect(mm.parse("45°", quantity: .angle) == 45)
        #expect(mm.parse("45 deg", quantity: .angle) == 45)
        #expect(mm.parse("6", quantity: .count) == 6)
    }

    @Test func radiusAndDiameterReadLikeLengths() {
        #expect(mm.parse("8 mm", quantity: .radius) == 8)
        #expect(inch.parse("1", quantity: .diameter) == 25.4)
    }

    @Test(arguments: ["", "abc", "12,5", "1/2", "1e3", "2 ft", "12 mm mm", "--3"])
    func refusesWhatItCannotReadExactly(_ text: String) {
        #expect(DocumentUnits().parse(text, quantity: .length) == nil)
    }

    @Test func refusesAUnitOfTheWrongQuantity() {
        #expect(mm.parse("45 mm", quantity: .angle) == nil)
        #expect(mm.parse("45°", quantity: .length) == nil)
        #expect(mm.parse("6.5", quantity: .count) == nil)
        #expect(mm.parse("6 mm", quantity: .count) == nil)
    }
}
