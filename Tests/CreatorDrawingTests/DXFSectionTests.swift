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
}
