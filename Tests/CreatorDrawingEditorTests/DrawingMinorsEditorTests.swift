import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUI
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Drawings minors, task 7: the DR-5 editor, paste and template slips.
@MainActor
@Suite("Drawings minors: editor")
struct DrawingMinorsEditorTests {
    private func assemblyHarness() -> (EditorHarness, DrawingView, [DrawingSourceOption]) {
        let sources = EditorHarness.sources(count: 3)
        let view = DrawingView(
            kind: .base, source: sources[0].id, orientation: .standard(.front), center: Vector2(100, 150),
            assembly: sources.map(\.id))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        return (EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, sources: sources), view, sources)
    }

    @Test func setSourceOnAnAssemblyIsRefused() {
        let (h, view, sources) = assemblyHarness()
        h.model.setSource(sources[2].id, of: view.id)
        #expect(h.model.refusal == "This view shows an assembly; change its parts in the Parts section.")
        #expect(h.log.commits.isEmpty)
        #expect(h.model.document.sheets[0].view(view.id)?.assembly == sources.map(\.id))
    }

    @Test func aReshownPartReturnsToItsPlace() {
        let (h, view, sources) = assemblyHarness()
        let ids = sources.map(\.id)
        h.model.setPart(ids[0], shown: false, of: view.id)
        h.model.setPart(ids[0], shown: true, of: view.id)
        #expect(h.model.document.sheets[0].view(view.id)?.assembly == ids)
    }

    @Test func replacingTheDocumentClearsTheBalloonFootAndPrunesBitmaps() throws {
        let (h, view, _) = assemblyHarness()
        let anchor = PickedAnchor(target: .point(.zero), shape: .point(.zero))
        h.model.balloonFoot = (BalloonDraft(view: view.id, anchor: anchor, hint: .zero), .zero)
        let pixels = try #require(GreyPixels(key: String(repeating: "b", count: 64), width: 2, height: 2, bytes: [0, 1, 2, 3]))
        _ = h.model.bitmaps.bitmap(for: pixels)
        #expect(h.model.bitmaps.count == 1)
        h.model.replaceDocument(h.model.document)
        #expect(h.model.balloonFoot == nil)
        #expect(h.model.bitmaps.count == 0)
        // A logo still in use keeps its bitmap.
        var sheet = h.model.document.sheets[0]
        sheet.titleBlock.logo = pixels.key
        var kept = h.model.document
        kept.sheets[0] = sheet
        h.model.replaceDocument(kept)
        _ = h.model.bitmaps.bitmap(for: pixels)
        h.model.replaceDocument(kept)
        #expect(h.model.bitmaps.count == 1)
    }

    @Test func removingALogoByACommitPrunesItsBitmap() throws {
        let pixels = try #require(GreyPixels(key: String(repeating: "c", count: 64), width: 2, height: 2, bytes: [0, 1, 2, 3]))
        var sheet = DrawingSheet(name: "Sheet 1")
        sheet.titleBlock.logo = pixels.key
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        _ = h.model.bitmaps.bitmap(for: pixels)
        h.model.setLogo(nil, of: sheet.id)
        #expect(h.model.bitmaps.count == 0)
    }

    @Test func aSymbolPastedWithItsDimensionButNotItsViewShiftsOnce() throws {
        let view = EditorDocuments.view(at: Vector2(100, 150))
        let value = DrawingDimension(
            kind: .linear(.horizontal), anchors: [.point(Vector2(0, 0)), .point(Vector2(10, 0))],
            placement: DimensionPlacement(offset: 8, angle: 0))
        let dimension = DrawingAnnotation(view: view.id, kind: .dimension(value))
        let datum = DrawingAnnotation(
            view: view.id, kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(dimension.id), distance: 4)))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: [dimension, datum])
        let made = SheetCopy.copy(views: [], annotations: [dimension, datum], onto: sheet, offset: Vector2(10, -10))
        #expect(made.annotations.count == 2)
        let copiedDatum = try #require(made.sheet.annotations.first { $0.symbolKind == .datum && $0.id != datum.id })
        guard case .datumFeature(let value) = copiedDatum.kind else { return }
        #expect(value.distance == 4)
    }

    @Test func aSymbolWhoseHostWasNotPastedIsRefused() {
        let view = EditorDocuments.view(at: Vector2(100, 150))
        let elsewhere = ViewID()
        let value = DrawingDimension(
            kind: .linear(.horizontal), anchors: [.point(Vector2(0, 0)), .point(Vector2(10, 0))],
            placement: DimensionPlacement(offset: 8, angle: 0))
        let dimension = DrawingAnnotation(view: elsewhere, kind: .dimension(value))
        let datum = DrawingAnnotation(
            view: view.id, kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(dimension.id), distance: 4)))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let made = SheetCopy.copy(views: [], annotations: [dimension, datum], onto: sheet, offset: Vector2(10, -10))
        #expect(made.annotations.isEmpty)
        #expect(made.skipped.contains(SheetCopy.symbolSentence))
    }

    @Test func clipboardKeysTakeNoOtherModifier() {
        #expect(SheetCanvasInput.key("c", modifiers: .primary) == .copy)
        #expect(SheetCanvasInput.key("c", modifiers: [.primary, .control]) == nil)
        #expect(SheetCanvasInput.key("v", modifiers: [.primary, .option]) == nil)
        #expect(SheetCanvasInput.key("x", modifiers: [.primary, .shift]) == nil)
        #expect(SheetCanvasInput.key("c", modifiers: [.primary, .command]) == .copy)
    }

    @Test func templateNamesAreTrimmedAndUnique() {
        let store = DrawingTemplateStore()
        let one = DrawingTemplateStoreTests.template("Acme")
        let two = DrawingTemplateStoreTests.template("Other")
        store.add(one)
        store.add(two)
        store.rename(two.id, to: "  Acme ")
        #expect(store.saveProblem == "Another template already has that name.")
        #expect(store.template(two.id)?.name == "Other")
        store.rename(two.id, to: "  Fresh ")
        #expect(store.template(two.id)?.name == "Fresh" && store.saveProblem == nil)
        store.rename(two.id, to: "Fresh")
        #expect(store.saveProblem == nil)
        store.add(DrawingTemplateStoreTests.template("Acme "))
        #expect(store.templates.map(\.name).contains("Acme 2"))
    }

    @Test func aMissingFolderHoldsNoTemplates() {
        let loaded = DrawingTemplateStoreTests.folder().load()
        #expect(loaded.templates.isEmpty && loaded.problems.isEmpty)
    }

    @Test func theExtensionFilterIgnoresCase() throws {
        let folder = DrawingTemplateStoreTests.folder()
        let template = DrawingTemplateStoreTests.template("Acme")
        try folder.save(template)
        let lower = folder.fileURL(for: template.id)
        let upper = lower.deletingLastPathComponent().appending(path: "\(template.id).MCTEMPLATE")
        try FileManager.default.moveItem(at: lower, to: upper)
        let loaded = folder.load()
        #expect(loaded.templates.map(\.id) == [template.id])
        try? FileManager.default.removeItem(at: folder.url)
    }

    @Test func aBalloonWithNoViewShowsNoItemRow() {
        let leader = LeaderEnd(target: .point(Vector2(1, 1)), hint: Vector2(1, 1))
        let annotation = DrawingAnnotation(view: nil, kind: .balloon(Balloon(leader: leader, offset: .zero)))
        #expect(BalloonInspector.view(of: annotation, in: DrawingSheet(name: "S")) == nil)
    }
}
