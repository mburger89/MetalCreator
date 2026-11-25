import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Dimensions in the app (drawings plan Task 14, R15, R22, R25, R26): one undo step each, the document's units, the last good values
/// saved without an edit, a lost dimension's number kept, the export's listed warnings and the DXF of a view with its annotations.
@MainActor
struct DrawingDimensionTests {
    func start(width: Double = 40, standard: DrawingStandard? = nil) async throws -> (AppModel, DimensionPlate, ViewID) {
        let plate = DimensionPlate(width: width)
        let app = await AppModel.inDrawing(plate.graph)
        if let standard { app.drawing.editor.setStandard(standard) }
        let view = try #require(await app.placeBaseView())
        return (app, plate, view)
    }

    func lose(_ app: AppModel, _ plate: DimensionPlate) async throws {
        try app.document.perform(plate.loseTheEdge, name: "Lose")
        await app.settle()
    }

    // MARK: Undo

    @Test func addingADimensionIsOneUndoStep() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        #expect(app.undoTitle == "Undo Add Dimension")
        #expect(app.texts(of: id).contains("40"), "\(app.texts(of: id))")
        app.undo()
        #expect(app.drawing.editor.document.sheets[0].annotations.isEmpty, "the editor follows an undo")
        app.redo()
        #expect(app.drawing.editor.document.sheets[0].annotation(id) != nil)
        await app.settle()
        #expect(app.report(of: id)?.status == .held)
    }

    @Test func aCancelledDragLeavesNoStep() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let editor = app.drawing.editor
        editor.press(.select)
        let name = try #require(app.document.undoName)
        let label = try #require(app.report(of: id)?.textCenter)
        let start = editor.transform.screenPoint(label)
        editor.primaryChanged(to: start, modifiers: [])
        for step in 1...6 { editor.primaryChanged(to: start + Vector2(0, Double(step) * 4), modifiers: []) }
        #expect(app.document.undoName != name, "the drag has made a step so far")
        let moved = editor.document
        editor.primaryCancelled()
        await app.settle()
        #expect(app.document.undoName == name, "a cancelled drag leaves no step")
        #expect(editor.document != moved)
        #expect(editor.document == app.document.drawings)
    }

    // MARK: Units

    @Test func anInchDocumentRestylesItsNumbers() async throws {
        let (app, _, view) = try await start(width: 40)
        let id = try #require(await app.dimensionBottomEdge(of: view))
        #expect(app.texts(of: id).contains("40"))
        try app.document.perform(.setUnits(DocumentUnits(length: .inches, precision: 3)), name: "Units")
        await app.settle()
        #expect(app.texts(of: id).contains("1.575"), "\(app.texts(of: id))")
        let (asme, _, aView) = try await start(width: 25, standard: .asme)
        let other = try #require(await asme.dimensionBottomEdge(of: aView))
        try asme.document.perform(.setUnits(DocumentUnits(length: .inches, precision: 3)), name: "Units")
        await asme.settle()
        #expect(asme.texts(of: other).contains(".984"), "ASME drops the leading zero: \(asme.texts(of: other))")
    }

    // MARK: Saving

    @Test func savingWritesLastGoodValuesWithoutAnEdit() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        #expect(app.drawing.editor.document.sheets[0].annotation(id)?.last == nil, "the document holds no last value yet")
        let steps = app.document.undoStack.undoEntries.count
        let url = temporaryURL("last.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let file = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry)
        #expect(file.graph.drawings.sheets[0].annotation(id)?.last?.values == [40])
        #expect(app.document.content == app.savedContent)
        #expect(app.document.undoStack.undoEntries.count == steps, "no undo step")
        #expect(!app.isEdited)
        #expect(app.document.drawings.sheets[0].annotation(id)?.last?.values == [40])
        #expect(app.drawing.editor.document == app.document.drawings, "the editor shows what is saved")
    }

    @Test func aReopenedLostDimensionShowsItsLastValue() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        try await lose(app, plate)
        #expect(app.texts(of: id).contains("40?"), "\(app.texts(of: id))")
        let url = temporaryURL("lost.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let file = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry)
        let reopened = AppModel(kernel: FakeKernel(), file: file, fileURL: url)
        await reopened.settle()
        reopened.setMode(.drawing)
        await reopened.settle()
        #expect(reopened.report(of: id)?.isLost == true)
        #expect(reopened.texts(of: id).contains("40?"), "\(reopened.texts(of: id))")
        let listed = reopened.drawing.editor.lostAnnotations
        #expect(listed.map(\.id) == [id])
        let pdf = temporaryURL("lost.pdf")
        defer { try? FileManager.default.removeItem(at: pdf) }
        _ = try await reopened.exportDrawingReturningWarnings(.pdf, to: pdf)
        let reader = try PDFStructureReader(data: Data(contentsOf: pdf))
        #expect(reader.pages.flatMap { $0.operators.filter { $0.name == "Tj" }.compactMap(\.operands.first) }.contains("(40?)"))
    }

    // MARK: Export warnings

    @Test func exportListsEachLostAnnotation() async throws {
        let (app, plate, view) = try await start()
        _ = try #require(await app.dimensionBottomEdge(of: view))
        _ = try #require(await app.dimensionBottomEdge(of: view, below: 14))
        try await lose(app, plate)
        let url = temporaryURL("lost.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.dxfSheet, to: url)
        let sentence = "On “Sheet 1”, “40?” lost what it was attached to: What it was attached to is no longer in the part."
        #expect(warnings.filter { $0.hasPrefix("On “Sheet 1”") } == [sentence, sentence], "\(warnings)")
    }

    @Test func exportListsAtMostTenPerSheet() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        try app.duplicateAnnotation(id, times: 12)
        try await lose(app, plate)
        let url = temporaryURL("many.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let warnings = try await app.exportDrawingReturningWarnings(.pdf, to: url)
        let sheet = warnings.filter { $0.hasPrefix("On “Sheet 1”") }
        #expect(sheet.count == 11, "\(sheet)")
        #expect(sheet.prefix(10).allSatisfy { $0.contains("“40?” lost what it was attached to") })
        #expect(sheet.last == "On “Sheet 1”, 3 more annotations lost what they were attached to.")
        let url2 = temporaryURL("eleven.pdf")
        defer { try? FileManager.default.removeItem(at: url2) }
        try app.duplicateAnnotation(id, times: 0)
        var drawings = app.drawing.editor.document
        let extra = drawings.sheets[0].annotations.map(\.id).dropFirst(11)
        for removed in extra { drawings.sheets[0].removeAnnotation(removed) }
        try app.document.perform(.setDrawings(drawings), name: "Trim")
        app.refreshDrawing()
        await app.settle()
        let eleven = try await app.exportDrawingReturningWarnings(.pdf, to: url2).filter { $0.hasPrefix("On “Sheet 1”") }
        #expect(eleven.last == "On “Sheet 1”, 1 more annotation lost what it was attached to.", "\(eleven)")
    }

    @Test func lostAnnotationsDontBlockAnExport() async throws {
        let (app, plate, view) = try await start()
        _ = try #require(await app.dimensionBottomEdge(of: view))
        try await lose(app, plate)
        for kind in DrawingExportKind.allCases where kind != .dxfView && kind != .dxfViewWithAnnotations {
            let url = temporaryURL("kept.\(kind.fileExtension)")
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try await app.exportDrawingReturningWarnings(kind, to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func aTypedSuffixOutsideWinAnsiWarnsOnce() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        app.drawing.editor.setSuffix("→", of: id)
        await app.settle()
        for kind in [DrawingExportKind.pdf, .dxfSheet] {
            let url = temporaryURL("arrow.\(kind.fileExtension)")
            defer { try? FileManager.default.removeItem(at: url) }
            let warnings = try await app.exportDrawingReturningWarnings(kind, to: url)
            let replacement = warnings.filter { $0.hasPrefix("The lettering can't draw some characters") }
            #expect(replacement.count == 1, "\(warnings)")
            #expect(replacement.first?.components(separatedBy: "→").count == 2, "quoted once: \(replacement)")
        }
    }

    // MARK: DXF of a view with its annotations

    @Test func dxfViewWithAnnotationsMeasuresTrue() async throws {
        let (app, _, view) = try await start()
        var drawings = app.drawing.editor.document
        var scaled = try #require(drawings.sheets[0].view(view))
        scaled.scale = DrawingScale(numerator: 1, denominator: 2)
        drawings.sheets[0].setView(scaled)
        try app.document.perform(.setDrawings(drawings), name: "Scale")
        await app.settle()
        _ = try #require(await app.dimensionBottomEdge(of: view))
        app.drawing.editor.selection = [view]
        let url = temporaryURL("annotated.dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await app.exportDrawingReturningWarnings(.dxfViewWithAnnotations, to: url)
        let reader = try DXFReader(data: Data(contentsOf: url))
        let uprights = reader.entities.filter { $0.type == "LINE" && $0.layer == "DIMENSION" }.filter {
            guard let x1 = $0.number(10), let x2 = $0.number(11) else { return false }
            return abs(x1 - x2) < 1e-6
        }
        let xs = uprights.compactMap { $0.number(10) }
        #expect(xs.count >= 2, "two extension lines")
        #expect(((xs.max() ?? 0) - (xs.min() ?? 0)).isApproximately(40), "model millimetres: \(xs)")
        let text = try #require(reader.entities.first { $0.type == "TEXT" })
        #expect(try #require(text.number(40)).isApproximately(5), "2.5 mm lettering at 1:2 is 5 mm of the part")
        let plain = temporaryURL("plain.dxf")
        defer { try? FileManager.default.removeItem(at: plain) }
        _ = try await app.exportDrawingReturningWarnings(.dxfView, to: plain)
        let bare = try DXFReader(data: Data(contentsOf: plain))
        #expect(!bare.entities.contains { $0.type == "TEXT" }, "DXF of a view at 1:1 stays geometry only")
    }

    @Test func theExportKindIsNamedAndListed() {
        #expect(DrawingExportKind.dxfViewWithAnnotations.title == "DXF")
        #expect(DrawingExportKind.dxfViewWithAnnotations.fileExtension == "dxf")
        #expect(AppCommands.drawingExportTitles.last == "Export DXF of View at 1:1 with Annotations…")
    }
}
