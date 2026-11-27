import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

/// Symbols and sheet notes in the DXF (DR-4 Task 6, plan R13).
@Suite struct DXFSymbolsTests {
    private let style = DrawingStyle.iso

    private func read(_ output: DXFOutput) throws -> DXFReader { try DXFReader(data: output.data) }

    private func symbolsOutput(_ picture: SheetPicture) -> DXFOutput { DXFWriter.sheet(picture, style: style) }

    @Test func symbolsAreOnTheDimensionLayer() throws {
        let parts = DrawingFixtures.symbolsSheetParts()
        let symbols = try read(symbolsOutput(parts.symbols)).records("ENTITIES")
        #expect(symbols.count > 50)
        // Every kind the symbols use: strokes (LINE, LWPOLYLINE), the circled modifiers (CIRCLE), the datum triangles (SOLID), text.
        #expect(Set(symbols.map(\.type)).isSuperset(of: ["LINE", "LWPOLYLINE", "CIRCLE", "SOLID", "TEXT"]), "\(Set(symbols.map(\.type)))")
        #expect(symbols.allSatisfy { $0.layer == "DIMENSION" })
        let notes = try read(symbolsOutput(parts.notes)).records("ENTITIES")
        #expect(notes.count > 5)
        #expect(notes.allSatisfy { $0.layer == "TEXT" })
        let whole = try read(symbolsOutput(DrawingFixtures.symbolsSheet())).records("ENTITIES")
        #expect(whole.count == symbols.count + notes.count)
        #expect(whole.allSatisfy { $0.layer == "DIMENSION" || $0.layer == "TEXT" })
    }

    @Test func aSymbolsSheetIsDeterministic() {
        for standard in [DrawingStandard.iso, .asme] {
            let first = DXFWriter.sheet(DrawingFixtures.symbolsSheet(standard: standard), style: .of(standard))
            let second = DXFWriter.sheet(DrawingFixtures.symbolsSheet(standard: standard), style: .of(standard))
            #expect(first.data == second.data)
        }
        let digest = SHA256.hash(symbolsOutput(DrawingFixtures.symbolsSheet()).data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "8f2bcbb3b0a1d823a3318577e4daabadbb2239fd7e8bb9051da091b87ec28afd")
    }
}
