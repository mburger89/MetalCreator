import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Datum, frame and surface symbols in the app (DR-4 R13, R21): one undo step each, the last good values saved without an edit, a
/// symbol on a dimension left to its dimension's refresh, and a symbol held through Group.
@MainActor
struct DrawingSymbolTests {
    func start(width: Double = 40) async throws -> (AppModel, DimensionPlate, ViewID) {
        let plate = DimensionPlate(width: width)
        let app = await AppModel.inDrawing(plate.graph)
        let view = try #require(await app.placeBaseView())
        return (app, plate, view)
    }

    @Test func addingADatumIsOneUndoStep() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.placeSymbol(.datum, on: view))
        #expect(app.undoTitle == "Undo Add Datum")
        app.undo()
        #expect(app.drawing.editor.document.sheets[0].annotation(id) == nil)
        app.redo()
        #expect(app.drawing.editor.document.sheets[0].annotation(id) != nil)
        await app.settle()
        #expect(app.report(of: id)?.status == .held)
    }

    @Test func aSymbolRefreshesItsLastGood() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.placeSymbol(.datum, on: view))
        app.setMode(.model)
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        let good = try #require(app.drawing.editor.remembered[id])
        guard case .attachment = good.figure else {
            Issue.record("the datum remembers its attachment figure: \(good.figure)")
            return
        }
        let saved = app.drawing.editor.documentForSaving()
        #expect(saved.sheets[0].annotation(id)?.last?.figure == good.figure)
    }

    @Test func aSymbolOnADimensionIsNotRefreshed() async throws {
        let (app, plate, view) = try await start()
        let dimension = try #require(await app.dimensionBottomEdge(of: view))
        let frame = try #require(await app.placeSymbol(.featureControlFrame, onDimension: dimension))
        app.setMode(.model)
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        #expect(app.drawing.editor.remembered[frame] == nil, "a frame on a dimension has no entry of its own")
        #expect(app.drawing.editor.remembered[dimension]?.values == [60])
    }

    @Test func savingWritesTheSymbolsLastGood() async throws {
        let (app, _, view) = try await start()
        let id = try #require(await app.placeSymbol(.datum, on: view))
        await app.settle()
        let url = temporaryURL("symbol.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        let edits = app.document.undoName
        try app.save(to: url)
        let file = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry)
        #expect(file.graph.drawings.sheets[0].annotation(id)?.last != nil)
        #expect(app.document.undoName == edits, "saving makes no step")
        #expect(!app.isEdited)
    }

    @Test func groupingKeepsASymbolHeld() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.placeSymbol(.datum, on: view))
        app.setMode(.model)
        app.editor.selection = [plate.box.rectangle.id, plate.box.extrude.id]
        app.editor.groupSelection()
        await app.settle()
        app.setMode(.drawing)
        await app.settle()
        #expect(app.report(of: id)?.status == .held, "\(String(describing: app.report(of: id)?.status))")
    }
}
