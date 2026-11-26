import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorApp

/// Symbols in the exports (DR-4 R13): they are on the PDF and the DXF, map back in a view's DXF, and the rules they break are
/// listed ten per sheet.
@MainActor
struct DrawingExportSymbolTests {
    func tj(_ page: PDFPage) -> [String] { page.operators.filter { $0.name == "Tj" }.compactMap(\.operands.first) }

    /// A 40 mm box with datum A on its bottom edge, a flatness 0.05 | A frame on its left edge (a form tolerance with a datum
    /// breaks R8) and a surface symbol.
    func marked() async throws -> (AppModel, ViewID, AnnotationID) {
        let app = await AppModel.inDrawing(DrawingBox(width: 40).graph)
        let view = try #require(await app.placeBaseView())
        _ = try #require(await app.placeSymbol(.datum, on: view))
        let frame = try #require(await app.placeSymbol(.featureControlFrame, on: view, side: .left))
        app.drawing.editor.setDatum(0, letterText: "A", material: nil, row: 0, of: frame)
        await app.settle()
        _ = try #require(await app.placeSymbol(.surfaceFinish, on: view))
        return (app, view, frame)
    }

    @Test func thePDFCarriesSymbols() async throws {
        let (app, _, _) = try await marked()
        let url = temporaryURL("symbols.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        let page = try #require(PDFStructureReader(data: Data(contentsOf: url)).pages.first)
        let texts = tj(page)
        #expect(texts.contains("(A)"), "\(texts)")
        #expect(texts.contains("(0.05)"), "\(texts)")
    }

    @Test func theSheetDXFHasSymbolsOnDimension() async throws {
        let (app, _, _) = try await marked()
        let url = temporaryURL("symbols.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.dxfSheet, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        let onDimension = reader.entities.filter { $0.layer == "DIMENSION" }
        #expect(onDimension.contains { $0.type == "LINE" })
        #expect(reader.entities.contains { $0.layer == "DIMENSION" && $0.type == "TEXT" }, "the symbols' letters and numbers")
    }

    @Test func aViewDXFWithAnnotationsMapsSymbolsBack() async throws {
        let app = await AppModel.inDrawing(DrawingBox(width: 40).graph)
        let view = try #require(await app.placeBaseView())
        try await app.editView(view) { $0.scale = DrawingScale(numerator: 1, denominator: 2) }
        _ = try #require(await app.placeSymbol(.datum, on: view))
        app.drawing.editor.selection = [view]
        let url = temporaryURL("datum.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.dxfViewWithAnnotations, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        let square = try #require(reader.entities.first { $0.layer == "DIMENSION" && $0.type == "LWPOLYLINE" })
        let xs = square.all(10).compactMap { Double($0) }
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        #expect(abs(width - 10) < 1e-6, "the datum square is 2h = 5 sheet mm, 10 model mm at 1 : 2: \(xs)")
    }

    @Test func aFlatnessWithADatumWarns() async throws {
        let (app, _, frame) = try await marked()
        let sentence = "Flatness is a form tolerance and takes no datum."
        #expect(app.report(of: frame)?.warnings == [sentence])
        let url = temporaryURL("warns.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        let label = try #require(app.report(of: frame)?.label)
        #expect(warnings == ["On “Sheet 1”, “\(label)”: \(sentence)"], "\(warnings)")
    }

    @Test func checksAreListedTenPerSheet() async throws {
        let app = await AppModel.inDrawing(DrawingBox(width: 40).graph)
        let view = try #require(await app.placeBaseView())
        _ = try #require(await app.placeSymbol(.datum, on: view))
        let frame = try #require(await app.placeSymbol(.featureControlFrame, on: view, side: .left))
        app.drawing.editor.setDatum(0, letterText: "A", material: nil, row: 0, of: frame)
        try app.duplicateAnnotation(frame, times: 11)
        await app.settle()
        let url = temporaryURL("many.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        let checks = warnings.filter { $0.hasPrefix("On “Sheet 1”, “") && $0.contains("takes no datum") }
        #expect(checks.count == 10, "\(warnings)")
        #expect(warnings.last == "On “Sheet 1”, 2 more symbols have warnings.", "\(warnings)")
    }
}
