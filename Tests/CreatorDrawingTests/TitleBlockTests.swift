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

    // MARK: DR-5 Task 5

    private func owner(_ standard: DrawingStandard) -> Rect2D {
        TitleBlockLayout.fields(for: standard).first { $0.key == .owner }!.rect
    }

    private func pixels(_ w: Int, _ h: Int) -> GreyPixels {
        GreyPixels(key: String(repeating: "a", count: 64), width: w, height: h, bytes: [UInt8](repeating: 128, count: w * h))!
    }

    @Test func theRevisionFieldFollowsTheTable() {
        var sheet = a3()
        sheet.titleBlock.revision = "typed"
        let plain = sheet
        let rows = [RevisionRow(letter: "A"), RevisionRow(letter: "B"), RevisionRow(letter: "C")]
        func texts(_ sheet: DrawingSheet) -> [String] {
            TitleBlockLayout.picture(
                sheet: sheet, settings: DrawingSettings(), facts: TitleBlockFacts(), sheetIndex: 0, sheetCount: 1
            ).texts.map(\.original)
        }
        #expect(texts(plain).contains("typed"))
        let withTable = DrawingSheet(
            name: "S", size: .a3, titleBlock: plain.titleBlock,
            annotations: [DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(rows: rows)))])
        let shown = texts(withTable)
        #expect(shown.contains("C") && !shown.contains("typed"))
        #expect(withTable.titleBlock.revision == "typed", "never overwritten")
    }

    @Test func theLogoSitsInTheOwnerField() {
        let field = Rect2D(min: Vector2(0, 30), max: Vector2(110, 40))
        #expect(owner(.iso) == field)
        let band = TitleBlockLayout.logoBand(in: field)
        #expect(band.min == Vector2(1.5, 31.5) && abs(band.max.y - 36.5) < 1e-9)
        let wide = TitleBlockLayout.logoRect(width: 200, height: 100, in: field)
        #expect(abs(wide.width - 10) < 1e-9 && abs(wide.height - 5) < 1e-9 && wide.min == Vector2(1.5, 31.5))
        let flat = TitleBlockLayout.logoRect(width: 1000, height: 50, in: field)
        #expect(abs(flat.width - 40) < 1e-9 && abs(flat.height - 2) < 1e-9)
        #expect(abs(flat.min.y - 33) < 1e-9 && abs(flat.max.y - 35) < 1e-9)
        for standard in [DrawingStandard.iso, .asme] {
            let rect = TitleBlockLayout.logoRect(width: 200, height: 100, in: owner(standard))
            let labelBottom = 37.5 - 1.8 * 207.0 / 718.0
            #expect(rect.max.y <= labelBottom - 0.4 && rect.min.y >= 30 && rect.max.x <= 110)
        }
        var sheet = a3()
        sheet.titleBlock.owner = "Acme"
        let picture = TitleBlockLayout.picture(
            sheet: sheet, settings: DrawingSettings(), facts: TitleBlockFacts(logo: .picture(pixels(200, 100))),
            sheetIndex: 0, sheetCount: 1)
        let origin = TitleBlockLayout.origin(for: sheet, standard: .iso)
        let image = picture.images[0]
        #expect(abs(image.rect.min.x - (origin.x + 1.5)) < 1e-9 && abs(image.rect.min.y - (origin.y + 31.5)) < 1e-9)
        let text = picture.texts.first { $0.original == "Acme" }!
        #expect(abs(text.origin.x - (image.rect.max.x + 1.5)) < 1e-9)
    }

    @Test func noLogoNoImage() {
        let picture = TitleBlockLayout.picture(
            sheet: a3(), settings: DrawingSettings(), facts: TitleBlockFacts(), sheetIndex: 0, sheetCount: 1)
        #expect(picture.images.isEmpty)
    }

    @Test func anUnreadableLogoGivesANotice() {
        #expect(SheetComposer.logoUnreadableSentence("it is damaged") == "The title block's logo couldn't be read: it is damaged")
        let sheet = a3()
        let document = DrawingDocument(sheets: [sheet])
        let facts = TitleBlockFacts(logo: .unreadable("it is damaged"))
        let screen = SheetComposer.compose(sheet, in: document, contents: [:], facts: facts)
        let notice = screen.texts.first { $0.isNotice }
        #expect(notice?.original == "The title block's logo couldn't be read: it is damaged" && screen.images.isEmpty)
        let file = SheetComposer.compose(sheet, in: document, contents: [:], facts: facts, notices: false)
        #expect(!file.texts.contains { $0.isNotice })
    }
}
