import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Drawings minors R2, R3, R19 and the SVG's text rules: what a file leaves out and says so.
@Suite("Export robustness")
struct ExportRobustnessTests {
    private func emptyViewSheet(notices: Bool) -> (SheetPicture, DrawingView) {
        let view = DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(150, 150))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [view.id: ViewContent()], facts: TitleBlockFacts(),
            notices: notices)
        return (picture, view)
    }

    @Test func anEmptyViewLeavesNoPlaceholderInTheDXFAndWarns() throws {
        let (screen, _) = emptyViewSheet(notices: true)
        let (file, view) = emptyViewSheet(notices: false)
        let frameStrokes = { (picture: SheetPicture) in picture.strokes.filter { $0.layer == .frame }.count }
        #expect(frameStrokes(screen) == frameStrokes(file) + 1, "the placeholder box is on screen only")
        let reader = try DXFReader(data: DXFWriter.sheet(file, style: .iso).data)
        let onFrame = reader.entities.filter { $0.layer == "FRAME" }.count
        let reference = try DXFReader(data: DXFWriter.sheet(screen, style: .iso).data).entities.filter { $0.layer == "FRAME" }.count
        #expect(onFrame == reference - 1)
        let warnings = file.fileWarnings()
        #expect(warnings.count == 1 && warnings[0].hasPrefix("View ") && warnings[0].hasSuffix(" has nothing drawn."), "\(warnings)")
        #expect(file.fileWarnings(view: view.id) == warnings)
        #expect(file.fileWarnings(view: ViewID()) == [])
    }

    @Test func aNonFiniteCoordinateIsLeftOutAndWarnsOnce() throws {
        var page = SheetPicture(size: Vector2(210, 297))
        let good = SheetStroke(segments: [.line(Vector2(1, 2), Vector2(3, 4))], width: 0.5, layer: .visible)
        page.strokes = [
            good,
            SheetStroke(segments: [.line(Vector2(0, 0), Vector2(.nan, 4))], width: 0.5, layer: .visible),
            SheetStroke(segments: [.arc(center: Vector2(0, 0), radius: .infinity, start: 0, sweep: 1)], width: 0.5, layer: .visible),
        ]
        page.fills = [SheetFill(points: [Vector2(0, 0), Vector2(1, .nan), Vector2(2, 0)])]
        #expect(page.nonFiniteCount == 3)
        #expect(page.fileWarnings() == ["Some lines couldn't be drawn because a measurement isn't a number."])
        let pdf = pdfText(PDFWriter.write([page], title: "T").data)
        #expect(pdf.contains("1 2 m") && !pdf.contains("nan") && !pdf.contains("inf"))
        let svg = try SVGStructureReader(data: SVGWriter.write(page, title: "T").data)
        #expect(svg.elements(named: "path").count == 1)
        let dxf = try DXFReader(data: DXFWriter.sheet(page, style: .iso).data)
        #expect(dxf.entities.filter { $0.type == "LINE" }.count == 1)
        #expect(dxf.entities.filter { $0.type == "SOLID" }.isEmpty)
    }

    @Test func theLogoNoticeStandsWithTheSheetNotes() throws {
        let sheet = DrawingSheet(name: "Sheet 1", views: [])
        var facts = TitleBlockFacts()
        facts.logo = .unreadable("The picture isn't in this document.")
        let picture = SheetComposer.compose(sheet, in: DrawingDocument(sheets: [sheet]), contents: [:], facts: facts)
        let notice = try #require(picture.texts.first { $0.isNotice })
        let frame = SheetFrame.rect(for: sheet, standard: .iso)
        let block = TitleBlockLayout.origin(for: sheet, standard: .iso)
        #expect(notice.origin.y >= block.y + TitleBlockLayout.height, "above the title block")
        #expect(notice.origin.x == block.x && notice.origin.x > frame.min.x + 2)
        let corner = Vector2(frame.min.x + 2, frame.min.y + 2)
        #expect(!picture.texts.contains { $0.isNotice && $0.origin == corner })
    }

    @Test func aNonFinitePictureIsLeftOutOfEveryExport() throws {
        var page = SheetPicture(size: Vector2(210, 297))
        page.images = [
            SheetImage(rect: Rect2D(min: Vector2(.nan, 0), max: Vector2(4, 3)), pixels: DrawingFixtures.logo),
            SheetImage(rect: Rect2D(min: Vector2(10, 20), max: Vector2(14, 23)), pixels: DrawingFixtures.logo),
        ]
        #expect(page.nonFiniteCount == 1 && page.fileWarnings() == [SheetPicture.notANumberSentence])
        #expect(try SVGStructureReader(data: SVGWriter.write(page, title: "T").data).elements(named: "image").count == 1)
        #expect(pdfText(PDFWriter.write([page], title: "T").data).components(separatedBy: " Do Q").count == 2)
        #expect(DXFWriter.sheet(page, style: .iso).leftOutNotANumber == 1)
    }

    @Test func theViewDXFGoesThroughTheSameFilter() throws {
        let view = DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(150, 150))
        let lines = [
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(10, 0)), source: nil),
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(.nan, 5)), source: nil),
        ]
        let output = DXFWriter.view(Projection2D(lines: lines), view: view, style: .iso)
        #expect(output.leftOutNotANumber >= 1)
        let reader = try DXFReader(data: output.data)
        #expect(!String(decoding: output.data, as: UTF8.self).lowercased().contains("nan"))
        #expect(reader.entities.filter { $0.type == "LINE" }.count == 1)
    }
}
