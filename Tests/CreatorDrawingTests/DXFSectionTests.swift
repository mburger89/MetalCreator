import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Hatch and cutting lines in the DXF (DR-3 Task 6).
@Suite struct DXFSectionTests {
    private let style = DrawingStyle.iso
    private let a4 = Rect2D(min: .zero, max: Vector2(210, 297))

    private func read(_ output: DXFOutput) throws -> DXFReader { try DXFReader(data: output.data) }

    private func fixture() -> DXFOutput {
        let sheet = DrawingFixtures.a4Sheet()
        return DXFWriter.write(strokes: sheet.strokes, texts: sheet.texts, extent: a4, style: style)
    }

    private func hatched(_ standard: DrawingStandard = .iso) -> DXFOutput {
        DXFWriter.sheet(DrawingFixtures.hatchedSheet(standard: standard), style: .of(standard))
    }

    @Test func hatchIsOnTheHatchLayer() throws {
        let reader = try read(hatched())
        let lines = reader.entities.filter { $0.layer == "HATCH" }
        #expect(lines.count >= 20)
        #expect(lines.allSatisfy { $0.type == "LINE" })
        #expect(lines.allSatisfy { $0.first(6) == nil })
    }

    @Test func aHatchedSheetIsDeterministic() {
        #expect(hatched().data == hatched().data)
        #expect(hatched(.asme).data == hatched(.asme).data)
    }

    @Test func aSolidStrokeOnTheCentreLayerIsContinuous() throws {
        func record(_ pattern: StrokePattern, _ layer: DrawingLayer) throws -> DXFRecord {
            let stroke = SheetStroke(segments: [.line(.zero, Vector2(10, 0))], width: 0.5, pattern: pattern, layer: layer)
            let output = DXFWriter.write(strokes: [stroke], texts: [], extent: a4, style: style)
            return try #require(try read(output).entities.first { $0.type == "LINE" })
        }
        #expect(try record(.solid, .center).first(6) == "Continuous")
        #expect(try record(.solid, .hidden).first(6) == "Continuous")
        #expect(try record(.centre, .center).first(6) == nil)
        #expect(try record(.hidden, .hidden).first(6) == nil)
        #expect(try record(.solid, .visible).first(6) == nil)
        let types = try read(fixture()).records("TABLES").filter { $0.type == "LTYPE" }.compactMap { $0.first(2) }
        #expect(types.contains("Continuous"))
    }

    @Test func theThickEndsAreContinuousInDXF() throws {
        let chain = try read(hatched()).entities.filter { $0.layer == "CENTER" }
        let solid = chain.filter { $0.first(6) == "Continuous" }
        let patterned = chain.filter { $0.first(6) == nil }
        #expect(!solid.isEmpty && !patterned.isEmpty)
        #expect(solid.count + patterned.count == chain.count)
        // Thick ends and corners: 2 ends and 2 corners; the thin chain: 3 pieces.
        #expect(solid.filter { $0.type == "LINE" }.count + solid.filter { $0.type == "LWPOLYLINE" }.count == 4)
        #expect(patterned.count == 3)
    }

    /// A section's cutting line on its parent comes with the parent's 1:1 DXF with annotations as the whole mark (the chain, both
    /// arrows and the letters), or not at all.
    @Test func aParentsViewDXFCarriesTheWholeCuttingLineOrNone() throws {
        let node = NodeID()
        let frame = StandardOrientation.front.frame
        let projection = Projection2D(lines: [
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(40, 0)), source: nil),
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(0, 20)), source: nil),
        ])
        let cutter = SectionCutter(frame: frame, points: [Vector2(5, 10), Vector2(35, 10)], viewing: Vector2(0, 1))
        let parent = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 150))
        let section = DrawingView(
            kind: .section, source: node, orientation: .custom(SectionFrame.frame(for: cutter)), center: Vector2(100, 80),
            showsLabel: true, derivation: .section(SectionLine(parent: parent.id, cutter: cutter)), letter: "A")
        let sheet = DrawingSheet(name: "S", views: [parent, section])
        let contents = [parent.id: ViewContent(projection: projection), section.id: ViewContent(projection: projection)]
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: contents, facts: TitleBlockFacts(), notices: false)
        let mapping = try #require(ViewMapping.of(content: contents[parent.id]!, center: parent.center, scale: sheet.scale.value))
        let own = picture.strokes.filter { $0.view == parent.id && $0.mark == section.id }
        let letters = picture.texts.filter { $0.mark == section.id }
        let arrows = picture.fills.filter { $0.mark == section.id }
        #expect(!own.isEmpty && arrows.count == 2 && letters.count == 2)

        let carried = try read(DXFWriter.view(projection, view: parent, style: style, annotations: (picture, mapping)))
        let bare = try read(DXFWriter.view(projection, view: parent, style: style))
        let marks = carried.entities.count - bare.entities.count
        // One entity per chain piece, per arrowhead and per letter: all of them are there.
        let pieces = own.reduce(0) { $0 + $1.segments.count }
        #expect(marks >= pieces + arrows.count + letters.count)
        #expect(carried.entities.filter { $0.type == "TEXT" || $0.type == "MTEXT" }.count == letters.count)
    }
}
