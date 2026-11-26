import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp

/// Section views in the app over FakeKernel (DR-3 R13, R14, R26): one undo step, a deleted parent, the last good refresh.
@MainActor
struct DrawingSectionTests {
    func make(_ kernel: FakeKernel = FakeKernel()) async -> (app: AppModel, base: ViewID, box: DrawingBox) {
        await kernel.setSectionCutHook { part, _, _ in part }
        let box = DrawingBox(width: 20)
        let app = await AppModel.inDrawing(box.graph, kernel: kernel)
        return (app, await app.placeBaseView() ?? ViewID(), box)
    }

    @Test func addingASectionIsOneUndoStep() async throws {
        let (app, base, _) = await make()
        let section = try #require(await app.addSection(on: base))
        #expect(app.undoTitle == "Undo Add View")
        #expect(!app.markStrokes(of: section).isEmpty, "the cutting line is drawn on the parent")
        #expect(app.drawing.editor.contents[section]?.hatch.isEmpty == false, "the cut face is hatched")
        app.undo()
        await app.settle()
        #expect(app.drawing.editor.document.sheets[0].view(section) == nil)
        #expect(app.markStrokes(of: section).isEmpty, "the marks went with it")
        app.redo()
        await app.settle()
        #expect(app.drawing.editor.document.sheets[0].view(section) != nil)
        #expect(!app.markStrokes(of: section).isEmpty)
        #expect(app.drawing.editor.contents[section]?.projection != nil)
    }

    @Test func undoBringsTheCuttingLineBack() async throws {
        let (app, base, _) = await make()
        let section = try #require(await app.addSection(on: base))
        app.drawing.editor.selection = [base]
        app.drawing.editor.deleteSelection()
        await app.settle()
        #expect(app.markStrokes(of: section).isEmpty)
        #expect(app.notices(of: section) == [DerivedViewNotices.sectionParentDeleted])
        app.undo()
        await app.settle()
        #expect(!app.markStrokes(of: section).isEmpty, "the marks return with the parent")
        #expect(app.notices(of: section).isEmpty, "and the notice goes")
    }

    @Test func aSectionRefreshesItsLastGood() async throws {
        // The section's annotations read the cut remainder, not the whole part: the hook hands back a narrower solid, and the
        // refresh after an evaluation asks the cache for the same cut the projection used.
        let kernel = FakeKernel()
        let (app, base, box) = await make(kernel)
        let section = try #require(await app.addSection(on: base))
        let box0 = try #require(app.drawing.editor.contents[section]?.projection?.bounds)
        let id = try #require(await app.dimensionEdge(of: section, at: Vector2(box0.center.x, box0.min.y)))
        let calls = await app.drawing.cache.cutCalls
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(30)), name: "Change Width")
        await app.settle()
        #expect(await app.drawing.cache.cutCalls == calls + 1, "projection and refresh share one cut")
        #expect(app.drawing.editor.remembered[id]?.values == [30])
        let key = try #require(app.drawing.refreshed[section])
        #expect(key.cutter != nil)
    }
}
