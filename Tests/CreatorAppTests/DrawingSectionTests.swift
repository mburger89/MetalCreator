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
        // The section's annotations read the cut remainder, not the whole part: the hook hands back a box 6 mm wide whatever the
        // part is, so a refresh that read the part (30 mm wide after the edit) would remember 30.
        let kernel = FakeKernel()
        let box = DrawingBox(width: 20)
        // Tagged as the extrude's own solid, so an annotation on the part's edge finds the remainder's too.
        let remainder = try await kernel.extrude(
            .rectangle(width: 6, height: 6, plane: .xy), distance: 6, mode: .oneSided, tag: NodeTag(node: box.extrude.id, item: 0))
        await kernel.setSectionCutHook { _, _, _ in remainder }
        let app = await AppModel.inDrawing(box.graph, kernel: kernel)
        let base = try #require(await app.placeBaseView())
        let section = try #require(await app.addSection(on: base))
        let box0 = try #require(app.drawing.editor.contents[section]?.projection?.bounds)
        #expect(box0.width == 6, "the section shows the remainder")
        let id = try #require(await app.dimensionEdge(of: section, at: Vector2(box0.center.x, box0.min.y)))
        // Called on its own, since the editor's own composing also remembers the remainder's figure: the refresh must read the cut
        // remainders (6 mm), and a job without the cutter reads the part (20 mm).
        let sheet = app.drawing.editor.document.sheets[0]
        let view = try #require(sheet.view(section))
        guard case .section(let line)? = view.derivation else { Issue.record("not a section"); return }
        let solids: [Solid]
        if case .ready(let held, _, _) = DrawingSession.content(of: view.source, in: app.document).state { solids = held } else {
            Issue.record("the source isn't ready"); return
        }
        func job(cutter: SectionCutter?) -> DrawingSession.RefreshJob {
            DrawingSession.RefreshJob(
                view: section, output: view.source, solids: solids,
                key: DrawingSession.RefreshKey(
                    solids: solids.map(ObjectIdentifier.init), frame: view.orientation.frame,
                    format: NumberFormat(units: app.document.units, settings: app.drawing.editor.document.settings),
                    annotations: sheet.annotations(of: section).filter { if case .note = $0.kind { false } else { true } },
                    cutter: cutter, tolerance: 0.01 / (view.scale ?? sheet.scale).value))
        }
        let cut = await DrawingSession.lastGood(of: job(cutter: line.cutter), cache: app.drawing.cache, kernel: kernel)
        #expect(cut[id]?.values == [6], "the remainder's figure: \(String(describing: cut[id]))")
        let whole = await DrawingSession.lastGood(of: job(cutter: nil), cache: app.drawing.cache, kernel: kernel)
        #expect(whole[id]?.values == [20], "without the cutter it reads the part: \(String(describing: whole[id]))")
        let calls = await app.drawing.cache.cutCalls
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(30)), name: "Change Width")
        await app.settle()
        #expect(await app.drawing.cache.cutCalls == calls + 1, "projection and refresh share one cut")
        #expect(app.drawing.editor.remembered[id]?.values == [6], "the remainder's figure, not the part's 30")
        let key = try #require(app.drawing.refreshed[section])
        #expect(key.cutter != nil)
    }
}
