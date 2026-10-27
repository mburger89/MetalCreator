import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The ANSI/ASME number rules of the dimension text (spec §5).
struct DimensionTextTests {
    let mm = DocumentUnits()
    let inch2 = DocumentUnits(length: .inches)
    let inch3 = DocumentUnits(length: .inches, precision: 3)

    func text(_ reading: DimensionReading, _ units: DocumentUnits = DocumentUnits()) -> String {
        DimensionStyle.ansi.text(reading, units: units)
    }

    @Test func millimetresKeepTheLeadingZeroAndDropTrailingZeros() {
        #expect(text(.init(0.5, .length)) == "0.5")
        #expect(text(.init(60, .length)) == "60")
        #expect(text(.init(12.25, .length)) == "12.3")
        #expect(text(.init(12.04, .length)) == "12")
    }

    @Test func inchesDropTheLeadingZeroAndKeepTrailingZeros() {
        #expect(text(.init(12.7, .length), inch2) == ".50")
        #expect(text(.init(57.15, .length), inch2) == "2.25")
        #expect(text(.init(57.15, .length), inch3) == "2.250")
        #expect(text(.init(76.2, .length), inch2) == "3.00")
        #expect(text(.init(6.35, .length), DocumentUnits(length: .inches, precision: 0)) == "0")
    }

    @Test func symbolsPrecedeTheNumber() {
        #expect(text(.init(17, .radius)) == "R17")
        #expect(text(.init(8, .diameter)) == "\u{D8}8")
        #expect(text(.init(45, .angle), inch2) == "45°")
        #expect(text(.init(22.25, .angle)) == "22.3°")
        #expect(text(.init(6, .count)) == "6X")
    }

    @Test func equalFeaturesArePrefixedNX() {
        #expect(text(.init(8, .diameter, count: 2)) == "2X Ø8")
        #expect(text(.init(8, .diameter, count: 1)) == "Ø8")
    }

    @Test func aReferenceWrapsTheWholeText() {
        #expect(text(.init(70, .length, isReference: true)) == "(70)")
        #expect(text(.init(8, .diameter, count: 2, isReference: true)) == "(2X Ø8)")
        #expect(text(.init(60, .length, name: "width")) == "width = 60")
        #expect(text(.init(60, .length, isReference: true, name: "width")) == "(width = 60)")
    }

    @Test func noNegativeZero() {
        #expect(text(.init(-0.01, .length)) == "0")
    }

    @Test func theAnsiStyleHasThreeToOneArrows() {
        #expect(DimensionStyle.ansi.arrowLength / DimensionStyle.ansi.arrowWidth == 3)
    }
}
