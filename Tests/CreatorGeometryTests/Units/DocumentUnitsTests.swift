import Foundation
import Testing
@testable import CreatorGeometry

struct DocumentUnitsTests {
    @Test func precisionDefaultsToOnePlaceInMillimetresAndTwoInInches() {
        #expect(DocumentUnits().fractionDigits == 1)
        #expect(DocumentUnits(length: .inches).fractionDigits == 2)
        #expect(DocumentUnits(precision: 9).fractionDigits == 4)
        #expect(DocumentUnits(precision: -1).fractionDigits == 0)
    }

    @Test func convertsThroughTwentyFivePointFour() {
        let inches = DocumentUnits(length: .inches)
        #expect(inches.value(fromMillimetres: 25.4) == 1)
        #expect(abs(inches.millimetres(fromValue: 2.25) - 57.15) < 1e-12)
    }

    @Test func millimetresIsTheDefaultDocument() {
        #expect(DocumentUnits.millimetres == DocumentUnits())
        #expect(DocumentUnits.precisionRange == 0...4)
        #expect(LengthUnit.inches.millimetresPerUnit == 25.4)
        #expect(LengthUnit.millimetres.symbol == "mm")
        #expect(LengthUnit.inches.title == "Inches")
    }

    @Test func encodesOnlyWhatDiffersFromTheDefault() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func json(_ units: DocumentUnits) throws -> String {
            String(bytes: try encoder.encode(units), encoding: .utf8) ?? ""
        }
        #expect(try json(DocumentUnits()) == "{}")
        #expect(try json(DocumentUnits(length: .inches)) == #"{"length":"in"}"#)
        #expect(try json(DocumentUnits(precision: 3)) == #"{"precision":3}"#)
        #expect(try json(DocumentUnits(length: .inches, precision: 3)) == #"{"length":"in","precision":3}"#)
    }

    @Test func decodesWithDefaultsAndClamps() throws {
        func decode(_ text: String) throws -> DocumentUnits {
            try JSONDecoder().decode(DocumentUnits.self, from: Data(text.utf8))
        }
        #expect(try decode("{}") == .millimetres)
        #expect(try decode(#"{"length":"furlong"}"#) == .millimetres)
        #expect(try decode(#"{"length":"in","precision":3}"#) == DocumentUnits(length: .inches, precision: 3))
        #expect(try decode(#"{"precision":12}"#).precision == 4)
        #expect(try decode(#"{"precision":-2}"#).precision == 0)
    }
}
