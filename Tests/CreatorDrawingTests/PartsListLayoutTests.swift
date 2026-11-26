import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

/// The parts list (DR-5 Task 5, R7).
@Suite("Parts list layout")
struct PartsListLayoutTests {
    private let plate = NodeID(), bolt = NodeID()
    private let corner = Vector2(200, 50)

    private func items(partNumbers: Bool = false) -> [NumberedItem] {
        [
            NumberedItem(part: plate, number: 1, material: "Steel", partNumber: partNumbers ? "P-1" : ""),
            NumberedItem(part: bolt, number: 2, material: "Zinc", partNumber: ""),
        ]
    }

    private var facts: [NodeID: PartFacts] {
        [plate: PartFacts(name: "Plate", quantity: 1, isRemoved: false), bolt: PartFacts(name: "Bolt", quantity: 4, isRemoved: false)]
    }

    private func draw(
        _ list: [NumberedItem], facts: [NodeID: PartFacts]? = nil, standard: DrawingStandard = .iso
    ) -> AnnotationDrawing {
        PartsListLayout.draw(list, facts: facts ?? self.facts, bottomRight: corner, standard: standard, h: 2.5)
    }

    @Test func theHeaderIsAtTheBottom() {
        let drawing = draw(items(partNumbers: true))
        let labels = drawing.texts.prefix(drawing.labelCount).map(\.original)
        #expect(labels == ["Item", "Qty", "Name", "Part number", "Material"])
        let headerY = drawing.texts[0].origin.y
        let one = drawing.texts.first { $0.original == "Plate" }
        #expect(abs((one?.origin.y ?? 0) - headerY - PartsListLayout.rowHeight) < 1e-9)
        let two = drawing.texts.first { $0.original == "Bolt" }
        #expect(abs((two?.origin.y ?? 0) - headerY - 2 * PartsListLayout.rowHeight) < 1e-9)
        #expect(abs(drawing.frame.min.y - corner.y) < 1e-9)
        #expect(abs(drawing.frame.height - PartsListLayout.height(rows: 2)) < 1e-9)
        #expect(abs(drawing.frame.max.x - corner.x) < 1e-9 && abs(drawing.frame.min.x - (corner.x - 180)) < 1e-9)
    }

    @Test func columnsAddUpTo180() {
        for standard in [DrawingStandard.iso, .asme] {
            for numbers in [true, false] {
                let columns = PartsListLayout.columns(for: standard, showsPartNumber: numbers)
                #expect(abs(columns.reduce(0) { $0 + $1.width } - 180) < 1e-9)
            }
        }
    }

    @Test func asmeColumnsRunTheOtherWay() {
        let titles = PartsListLayout.columns(for: .asme, showsPartNumber: true).map(\.title)
        #expect(titles == ["QTY", "PART NO.", "DESCRIPTION", "MATERIAL", "ITEM"])
    }

    @Test func noPartNumberNoColumn() {
        #expect(!draw(items()).texts.contains { $0.original == "Part number" })
        let columns = PartsListLayout.columns(for: .iso, showsPartNumber: false)
        #expect(columns.map(\.title) == ["Item", "Qty", "Name", "Material"] && columns[2].width == 110)
    }

    @Test func aLongNameIsFitted() {
        let long = String(repeating: "Wide ", count: 30)
        let drawing = draw(
            [NumberedItem(part: plate, number: 1, material: "", partNumber: "")],
            facts: [plate: PartFacts(name: long, quantity: 1, isRemoved: false)])
        let text = drawing.texts.first { $0.original == long }
        #expect(text != nil)
        let width = PartsListLayout.columns(for: .iso, showsPartNumber: false)[2].width - 3
        #expect((text?.run.width ?? 1000) <= width + 1e-9 && (text?.height ?? 9) < 2.5)
        let cut = String(repeating: "W", count: 200)
        let cutDrawing = draw(
            [NumberedItem(part: plate, number: 1, material: "", partNumber: "")],
            facts: [plate: PartFacts(name: cut, quantity: 1, isRemoved: false)])
        #expect(cutDrawing.texts.contains { $0.original == cut && $0.run.width <= width + 1e-9 })
    }

    @Test func unknownQuantityReadsAQuestionMark() {
        let drawing = draw(
            [NumberedItem(part: plate, number: 1, material: "", partNumber: "")],
            facts: [plate: PartFacts(name: "Plate", quantity: nil, isRemoved: false)])
        #expect(drawing.texts.contains { $0.original == "?" })
        let removed = draw(
            [NumberedItem(part: plate, number: 1, material: "", partNumber: "")],
            facts: [plate: PartFacts(name: "Plate", quantity: nil, isRemoved: true)])
        #expect(removed.texts.contains { $0.original == "Plate?" })
        let nameless = draw(
            [NumberedItem(part: plate, number: 1, material: "", partNumber: "")],
            facts: [plate: PartFacts(name: "?", quantity: nil, isRemoved: true)])
        #expect(nameless.texts.filter { $0.original == "?" }.count == 2)
    }

    @Test func anEmptyListDrawsItsHeader() {
        let drawing = draw([])
        #expect(drawing.texts.count == 4 && drawing.labelCount == 4)
        #expect(abs(drawing.frame.height - PartsListLayout.rowHeight) < 1e-9 && drawing.segments.count == 3)
    }

    @Test func linesOnFrameCellsOnText() {
        let source = DrawingView(kind: .base, source: plate, orientation: .standard(.top), center: .zero)
        let withView = DrawingSheet(
            name: "S", size: .a3, views: [source], annotations: [DrawingAnnotation(view: nil, kind: .partsList(PartsList()))])
        let document = DrawingDocument(sheets: [withView])
        let facts = TitleBlockFacts(parts: [plate: PartFacts(name: "Plate", quantity: 1, isRemoved: false)])
        let picture = SheetComposer.compose(withView, in: document, contents: [:], facts: facts)
        let id = withView.annotations[0].id
        let strokes = picture.strokes.filter { $0.annotation == id }
        let style = DrawingStyle.iso
        #expect(strokes.contains { $0.width == style.frame && $0.layer == .frame })
        #expect(strokes.contains { $0.width == style.zone && $0.layer == .frame })
        #expect(strokes.allSatisfy { $0.layer == .frame })
        let texts = picture.texts.filter { $0.annotation == id }
        #expect(texts.first { $0.original == "Plate" }?.layer == .text)
        #expect(texts.first { $0.original == "Item" }?.layer == .frame)
        #expect(picture.annotationReports[id]?.label == "Parts list")
    }
}
