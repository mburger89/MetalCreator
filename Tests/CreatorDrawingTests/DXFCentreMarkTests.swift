import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

/// A view's 1:1 DXF with annotations keeps the automatic centre marks of its holes (final review).
@Suite struct DXFCentreMarkTests {
    private let style = DrawingStyle.iso

    @Test func aViewWithAnnotationsKeepsItsAutomaticCentreMarks() throws {
        let circle = ProjectedLine(
            visibility: .visible, lineClass: .sharp,
            curve: .arc(center: Vector2(10, 10), radius: 3, start: 0, sweep: 2 * .pi), source: .edge(EdgeID(0)))
        let projection = Projection2D(lines: [circle])
        var onSheet = DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(150, 150))
        onSheet.scale = nil
        let sheet = DrawingSheet(name: "S", scale: DrawingScale(numerator: 1, denominator: 1), views: [onSheet])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [onSheet.id: ViewContent(projection: projection)],
            facts: TitleBlockFacts())
        let mapping = try #require(ViewMapping.of(projection: projection, center: onSheet.center, scale: 1))
        let plain = try DXFReader(data: DXFWriter.view(projection, view: onSheet, style: style).data)
        #expect(!plain.entities.contains { $0.layer == "CENTER" })
        let annotated = try DXFReader(
            data: DXFWriter.view(projection, view: onSheet, style: style, annotations: (picture, mapping)).data)
        #expect(annotated.entities.filter { $0.layer == "CENTER" }.count == 2, "the two chain lines of the hole's centre mark")
    }

    @Test func aSmallCentreMarkIsContinuous() throws {
        let radius = AnnotationStyle.iso.smallCentre / 4
        let circle = ProjectedLine(
            visibility: .visible, lineClass: .sharp,
            curve: .arc(center: Vector2(10, 10), radius: radius, start: 0, sweep: 2 * .pi), source: .edge(EdgeID(0)))
        let projection = Projection2D(lines: [circle])
        let onSheet = DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(150, 150))
        let sheet = DrawingSheet(name: "S", scale: DrawingScale(numerator: 1, denominator: 1), views: [onSheet])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [onSheet.id: ViewContent(projection: projection)],
            facts: TitleBlockFacts())
        let marks = picture.strokes.filter { $0.layer == .center }
        #expect(marks.count == 2 && marks.allSatisfy { $0.pattern == .solid }, "a cross, solid on screen")
        let output = DXFWriter.sheet(picture, style: style)
        let lines = try DXFReader(data: output.data).entities.filter { $0.layer == "CENTER" }
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.first(6) == "Continuous" })
    }
}
