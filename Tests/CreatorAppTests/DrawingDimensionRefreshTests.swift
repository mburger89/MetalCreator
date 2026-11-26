import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Dimensions after a model edit (drawings plan R25, R26): the last good value follows the model outside Drawing mode and on sheets
/// that aren't shown, and a view being re-projected keeps its dimensions held.
extension DrawingDimensionTests {
    // MARK: Refreshing after an evaluation (R26)

    @Test func aModelEditOutsideDrawingModeRefreshesTheLastValue() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        app.setMode(.model)
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        #expect(app.drawing.editor.remembered[id]?.values == [60], "the value follows the model with no compose")
        try await lose(app, plate)
        #expect(app.drawing.editor.remembered[id]?.values == [60], "a lost annotation never erases what is remembered")
        app.setMode(.drawing)
        await app.settle()
        #expect(app.texts(of: id).contains("60?"), "\(app.texts(of: id))")
        let url = temporaryURL("sixty.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let file = try GraphFileIO.decode(Data(contentsOf: url), registry: BuiltInNodes.registry)
        #expect(file.graph.drawings.sheets[0].annotation(id)?.last?.values == [60])
    }

    @Test func anotherSheetsDimensionIsRefreshed() async throws {
        let (app, plate, view) = try await start()
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let first = try #require(app.drawing.editor.currentSheet)
        app.drawing.editor.addSheet()
        await app.settle()
        app.drawing.editor.show(sheet: first)
        await app.settle()
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        // A second sheet with a view of its own, whose dimension isn't shown.
        let second = try #require(app.drawing.editor.document.sheets.last?.id)
        app.drawing.editor.show(sheet: second)
        let other = try #require(await app.placeBaseView())
        let onSecond = try #require(await app.dimensionBottomEdge(of: other))
        app.drawing.editor.show(sheet: first)
        await app.settle()
        try app.document.perform(plate.setWidth(70), name: "Width")
        await app.settle()
        try app.document.perform(plate.loseTheEdge, name: "Lose")
        await app.settle()
        let saved = app.drawing.editor.documentForSaving()
        #expect(saved.sheet(second)?.annotation(onSecond)?.last?.values == [70])
        #expect(saved.sheets[0].annotation(id)?.last?.values == [70])
    }

    @Test func showingASheetNeverFeedsItsOldValueBack() async throws {
        let (app, plate, view) = try await start()
        _ = try #require(await app.dimensionBottomEdge(of: view))
        let first = try #require(app.drawing.editor.currentSheet)
        app.drawing.editor.addSheet()
        await app.settle()
        let second = try #require(app.drawing.editor.document.sheets.last?.id)
        let other = try #require(await app.placeBaseView())
        let onSecond = try #require(await app.dimensionBottomEdge(of: other))
        app.drawing.editor.show(sheet: first)
        await app.settle()
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        try await lose(app, plate)
        app.drawing.editor.show(sheet: second)
        await app.settle()
        #expect(app.texts(of: onSecond).contains("60?"), "\(app.texts(of: onSecond))")
        #expect(app.drawing.editor.remembered[onSecond]?.values == [60])
        #expect(app.drawing.editor.documentForSaving().sheet(second)?.annotation(onSecond)?.last?.values == [60])
    }

    @Test func enteringDrawingWithTwoViewsNeverFeedsAnOldValueBack() async throws {
        let (app, plate, view) = try await start()
        let first = try #require(await app.dimensionBottomEdge(of: view))
        let second = try #require(await app.placeBaseView(at: Vector2(150, 50)))
        let onSecond = try #require(await app.dimensionBottomEdge(of: second))
        app.setMode(.model)
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.settle()
        try await lose(app, plate)
        app.setMode(.drawing)
        await app.settle()
        for id in [first, onSecond] {
            #expect(app.texts(of: id).contains("60?"), "\(app.texts(of: id))")
            #expect(app.drawing.editor.remembered[id]?.values == [60])
        }
    }

    // MARK: Projection in flight (R25)

    @Test func anEditKeepsDimensionsHeldWhileReprojecting() async throws {
        let kernel = FakeKernel()
        let plate = DimensionPlate(width: 40)
        let app = await AppModel.inDrawing(plate.graph, kernel: kernel)
        let view = try #require(await app.placeBaseView())
        let id = try #require(await app.dimensionBottomEdge(of: view))
        let gate = HookGate()
        defer { gate.open() }
        await kernel.setProjectionHook { await gate.hold() }
        try app.document.perform(plate.setWidth(60), name: "Width")
        await app.document.waitForEvaluation()
        app.refreshDrawing()
        await gate.waitUntilEntered()
        let during = try #require(app.report(of: id))
        #expect(during.status == .held, "held against the topology it was measured on")
        #expect(during.label == "40")
        #expect(app.drawing.editor.lostAnnotations.isEmpty, "and not listed as lost")
        gate.open()
        await app.settle()
        #expect(app.report(of: id)?.label == "60")
        #expect(app.report(of: id)?.status == .held)
    }
}
