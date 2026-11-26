import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Title block")
struct TitleBlockTests {
    private func a3() -> DrawingSheet {
        DrawingSheet(
            name: "Sheet 1", size: .a3, scale: DrawingScale(numerator: 1, denominator: 2),
            titleBlock: TitleBlock(owner: "Acme", title: "Bracket"))
    }

    @Test func theBlockSitsInTheFramesCorner() {
        let picture = TitleBlockLayout.picture(
            sheet: a3(), settings: DrawingSettings(), facts: TitleBlockFacts(), sheetIndex: 0, sheetCount: 1)
        let outline = picture.strokes[0]
        #expect(outline.bounds == Rect2D(min: Vector2(230, 10), max: Vector2(410, 50)))
    }

    @Test func fieldsMatchTheTable() {
        let fields = TitleBlockLayout.fields(for: .iso)
        #expect(fields.count == 13 && fields.map(\.key) == TitleBlockKey.allCases)
        let title = fields[3]
        #expect(title.key == .title && title.rect == Rect2D(min: Vector2(0, 10), max: Vector2(110, 30)))
        #expect(title.valueHeight == 7)
        let origin = TitleBlockLayout.origin(for: a3(), standard: .iso)
        #expect(origin == Vector2(230, 10))
        #expect(TitleBlockKey.allCases.filter(\.isTyped).count == 7)
    }

    @Test func automaticValues() {
        func texts(_ standard: DrawingStandard, size: SheetSize) -> [String] {
            var sheet = a3()
            sheet.size = size
            let settings = DrawingSettings(standard: standard)
            return TitleBlockLayout.picture(
                sheet: sheet, settings: settings, facts: TitleBlockFacts(), sheetIndex: 1, sheetCount: 3
            ).texts.map(\.original)
        }
        let iso = texts(.iso, size: .a3)
        #expect(iso.contains("A3") && iso.contains("2 / 3") && iso.contains("1 : 2"))
        let asme = texts(.asme, size: .ansiB)
        #expect(asme.contains("B") && asme.contains("2 OF 3") && asme.contains("1:2"))
    }

    @Test func massText() {
        #expect(TitleBlockFacts.massText(grams: 8.4, inches: false) == "8.4 g")
        #expect(TitleBlockFacts.massText(grams: 84, inches: false) == "84 g")
        #expect(TitleBlockFacts.massText(grams: 1234, inches: false) == "1.234 kg")
        #expect(TitleBlockFacts.massText(grams: 9.96, inches: false) == "10 g", "rounds up into the whole-gram form")
        #expect(TitleBlockFacts.massText(grams: 9.94, inches: false) == "9.9 g")
        #expect(TitleBlockFacts.massText(grams: 999.6, inches: false) == "1.000 kg", "rounds up into the kilogram form")
        #expect(TitleBlockFacts.massText(grams: 999.4, inches: false) == "999 g")
        #expect(TitleBlockFacts.massText(grams: 1234.2, inches: true) == "2.721 lb")
    }

    @Test func anEmptyMassLeavesTheFieldEmpty() {
        let empty = TitleBlockLayout.picture(
            sheet: a3(), settings: DrawingSettings(), facts: TitleBlockFacts(massText: nil), sheetIndex: 0, sheetCount: 1)
        let filled = TitleBlockLayout.picture(
            sheet: a3(), settings: DrawingSettings(), facts: TitleBlockFacts(massText: "84 g"), sheetIndex: 0, sheetCount: 1)
        #expect(!empty.texts.contains { $0.original == "84 g" })
        #expect(filled.texts.contains { $0.original == "84 g" })
        #expect(filled.texts.count == empty.texts.count + 1)
    }

    @Test func labelsPerStandard() {
        #expect(TitleBlockLayout.fields(for: .iso).map(\.label).prefix(4) == ["Owner", "Drawn by", "Date", "Title"])
        #expect(TitleBlockLayout.fields(for: .asme).map(\.label).prefix(4) == ["COMPANY", "DRAWN", "DATE", "TITLE"])
        #expect(TitleBlockLayout.fields(for: .asme)[12].label == "TOLERANCES")
        #expect(TitleBlockLayout.fields(for: .iso)[7].label.isEmpty)
    }
}
