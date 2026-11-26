import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The DR-5 inspector pages: balloons, the parts list, the revision table, an assembly view's parts, the logo and the templates
/// (DR-5 R1, R4, R5, R7, R9, R10, R11, R20).
@MainActor
@Suite("Drawing inspector DR-5 pages")
struct DrawingInspectorAssemblyTests {
    private func harness() -> (EditorHarness, [DrawingView]) {
        let views = [EditorDocuments.view(at: Vector2(100, 100)), EditorDocuments.view(at: Vector2(200, 100))]
        let sheet = DrawingSheet(name: "Sheet 1", views: views)
        return (EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id), views)
    }
    private func texts(_ window: DrawingWindow) throws -> [String] {
        try window.window.elements(role: .staticText).compactMap { $0.value ?? $0.label }
    }

    private func open(_ model: DrawingEditorModel) async throws -> DrawingWindow {
        try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(1200)), scaleFactor: 1) {
            DrawingInspector(model: model)
        }
    }

    private func press(_ window: DrawingWindow, label: String, index: Int = 0) throws {
        let found = try window.window.elements(where: { $0.label == label })
        let one = try #require(found.indices.contains(index) ? found[index] : nil, "no \(label) \(index)")
        window.window.click(at: Point(x: one.frame.origin.x + 4, y: one.frame.origin.y + 4))
    }

    private func table(_ rows: [RevisionRow] = []) -> DrawingAnnotation {
        DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(rows: rows)))
    }

    private func requesting(_ sheet: DrawingSheet, _ requests: Box<[DrawingEditorRequest]>) -> DrawingEditorModel {
        let model = DrawingEditorModel(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, today: { "2026-11-24" },
            events: DrawingEditorEvents(committed: { _ in }, requested: { requests.value.append($0) }))
        model.visibleRect = Rect2D(min: .zero, max: Vector2(1000, 600))
        return model
    }

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private let balloonOnSecond: (NodeID, NodeID) -> DrawingAnnotation = { _, second in
        AssemblyScene.balloonAnnotation(on: second, edge: 102, copy: 1, offset: Vector2(10, 10))
    }

    @Test func aBalloonPageNamesItsItem() async throws {
        let s = AssemblyScene.make(annotations: [balloonOnSecond])
        s.h.model.partFacts = [
            s.first: PartFacts(name: "Left", quantity: 1, isRemoved: false),
            s.second: PartFacts(name: "Right", quantity: 1, isRemoved: false),
        ]
        s.h.model.selectedAnnotations = [try #require(s.annotations.first).id]
        let window = try await open(s.h.model)
        let shown = try texts(window)
        #expect(shown.contains("Balloon"), "\(shown)")
        #expect(shown.contains("Item 2 · Right"), "\(shown)")
        try press(window, label: "Delete")
        #expect(s.h.log.commits.map(\.name) == ["Delete Balloon"])
    }

    @Test func aRemovedPartCanBeUnticked() async throws {
        let a = DrawingSourceOption(id: NodeID(), name: "A", bounds: nil)
        let b = DrawingSourceOption(id: NodeID(), name: "B", bounds: nil)
        let removed = NodeID()
        let view = DrawingView(
            kind: .base, source: a.id, orientation: .standard(.front), center: Vector2(100, 100),
            assembly: [a.id, b.id, removed])
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, sources: [a, b])
        h.model.partFacts = [removed: PartFacts(name: "Plate", quantity: nil, isRemoved: true)]
        h.model.selection = [view.id]
        let window = try await open(h.model)
        let names = ["A", "B", "Plate (removed)"]
        let found = try names.map { name in try window.window.element(label: name) }
        let order = found.map(\.frame.origin.y)
        #expect(order == order.sorted(), "A, B, then the removed part: \(order)")
        try press(window, label: "Plate (removed)")
        #expect(h.log.commits.map(\.name) == ["Change Parts"])
        #expect(h.model.document.sheets[0].views[0].assembly == [a.id, b.id])
    }

    @Test func anAssemblyViewShowsParts() async throws {
        let s = AssemblyScene.make()
        s.h.model.selection = [s.view.id]
        let window = try await open(s.h.model)
        let shown = try texts(window)
        #expect(shown.contains("PARTS"), "\(shown)")
        #expect(!shown.contains("Source"), "no Source menu: \(shown)")
        _ = try window.window.element(label: "Left")
        _ = try window.window.element(label: "Right")
        try press(window, label: "Right")
        #expect(s.h.log.commits.map(\.name) == ["Change Parts"])
        #expect(s.h.model.document.sheets[0].views[0].assembly == [s.first])
    }

    @Test func aSingleOutputViewKeepsItsSource() async throws {
        let (h, views) = harness()
        h.model.selection = [views[0].id]
        let window = try await open(h.model)
        let shown = try texts(window)
        #expect(shown.contains("Source") && !shown.contains("PARTS"), "\(shown)")
    }

    private func listScene() -> (EditorHarness, NodeID, NodeID, AnnotationID) {
        let s = AssemblyScene.make()
        let list = DrawingAnnotation(view: nil, kind: .partsList(PartsList()))
        var sheet = s.h.model.document.sheets[0]
        sheet.setAnnotation(list)
        var document = s.h.model.document
        document.sheets[0] = sheet
        s.h.model.replaceDocument(document)
        s.h.model.partFacts = [
            s.first: PartFacts(name: "Left", quantity: 1, isRemoved: false),
            s.second: PartFacts(name: "Right", quantity: nil, isRemoved: false),
        ]
        s.h.model.selectedAnnotations = [list.id]
        return (s.h, s.first, s.second, list.id)
    }

    @Test func thePartsListPageEditsItems() async throws {
        let (h, first, second, _) = listScene()
        let window = try await open(h.model)
        let shown = try texts(window)
        #expect(shown.contains("Parts list") && shown.contains("Item 1 · Left") && shown.contains("Item 2 · Right"), "\(shown)")
        #expect(shown.contains("?"), "an unknown quantity reads ?: \(shown)")
        let field = try #require(try window.window.elements(role: .textField).first)
        window.window.click(at: Point(x: field.frame.origin.x + 4, y: field.frame.origin.y + 4))
        try await window.window.runUntilIdle()
        window.window.typeText("S235")
        window.window.typeKey(.return)
        try await window.window.runUntilIdle()
        #expect(h.log.commits.map(\.name) == ["Change Item"])
        #expect(h.model.document.items.first { $0.part == first }?.material == "S235")
        try press(window, label: "Move Down", index: 0)
        try await window.window.runUntilIdle()
        #expect(h.log.commits.map(\.name) == ["Change Item", "Move Item"])
        #expect(h.model.document.items.map(\.part) == [second, first])
        let up = try window.window.elements(where: { $0.label == "Move Up" })
        #expect(up.count == 2, "a Move Up for each item")
    }

    @Test func theRevisionPageAddsAndEdits() async throws {
        let row = RevisionRow(letter: "A", description: "First issue", date: "2026-01-02", approved: "MB")
        let annotation = table([row])
        let sheet = DrawingSheet(name: "Sheet 1", annotations: [annotation])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.selectedAnnotations = [annotation.id]
        let window = try await open(h.model)
        let shown = try texts(window)
        #expect(shown.contains("Revision table") && shown.contains("A"), "\(shown)")
        try press(window, label: "New Revision")
        try await window.window.runUntilIdle()
        #expect(h.log.commits.map(\.name) == ["Add Revision"])
        guard case .revisionTable(let now)? = h.model.sheet?.annotation(annotation.id)?.kind else {
            Issue.record("no table")
            return
        }
        #expect(now.rows.map(\.letter) == ["A", "B"] && now.rows[1].date.isEmpty, "the date is the person's to type")
        let fields = try window.window.elements(role: .textField)
        let description = try #require(fields.first { $0.value == "First issue" })
        window.window.click(at: Point(x: description.frame.origin.x + 4, y: description.frame.origin.y + 4))
        try await window.window.runUntilIdle()
        window.window.typeKey(.end)
        window.window.typeText("!")
        window.window.typeKey(.return)
        try await window.window.runUntilIdle()
        #expect(h.log.commits.map(\.name) == ["Add Revision", "Change Revision"])
        try press(window, label: "Remove Last Revision")
        try await window.window.runUntilIdle()
        #expect(h.log.commits.map(\.name).last == "Remove Revision")
    }

    @Test func theSheetPageHasLogoAndTemplates() async throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        let requests = Box<[DrawingEditorRequest]>([])
        let model = requesting(sheet, requests)
        model.templateChoices = [DrawingTemplateChoice(id: "t1", name: "Acme")]
        let window = try await open(model)
        let shown = try texts(window)
        #expect(shown.contains("TEMPLATES") && shown.contains("Logo"), "\(shown)")
        #expect(try window.window.elements(where: { $0.label == "Remove Logo" }).isEmpty, "no logo, nothing to remove")
        try press(window, label: "Choose Logo…")
        try press(window, label: "Save Sheet as Template")
        try press(window, label: "Delete")
        #expect(requests.value == [.chooseLogo(sheet.id), .saveSheetAsTemplate(sheet.id), .deleteTemplate("t1")])
        let name = try #require(try window.window.elements(role: .textField).first { $0.value == "Acme" })
        window.window.click(at: Point(x: name.frame.origin.x + 4, y: name.frame.origin.y + 4))
        try await window.window.runUntilIdle()
        window.window.typeKey(.end)
        window.window.typeText("s")
        window.window.typeKey(.return)
        try await window.window.runUntilIdle()
        #expect(requests.value.last == .renameTemplate("t1", to: "Acmes"))
    }

    @Test func aLogoCanBeRemoved() async throws {
        let hash = String(repeating: "ab", count: 32)
        let sheet = DrawingSheet(name: "Sheet 1", titleBlock: TitleBlock(logo: hash))
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        let window = try await open(h.model)
        try press(window, label: "Remove Logo")
        #expect(h.log.commits.map(\.name) == ["Change Logo"])
        #expect(h.model.document.sheets[0].titleBlock.logo == nil)
    }

    @Test func theRevisionFieldIsReadOnlyWithATable() async throws {
        let plain = DrawingSheet(name: "Sheet 1", titleBlock: TitleBlock(revision: "C"))
        let one = EditorHarness(document: EditorDocuments.document([plain]), sheet: plain.id)
        let typed = try await open(one.model)
        #expect(try typed.window.elements(role: .textField).contains { $0.value == "C" })
        #expect(!(try texts(typed).contains("From the revision table")))
        let rows = DrawingSheet(
            name: "Sheet 1", titleBlock: TitleBlock(revision: "C"), annotations: [table([RevisionRow(letter: "A")])])
        let two = EditorHarness(document: EditorDocuments.document([rows]), sheet: rows.id)
        let shown = try await open(two.model)
        #expect(try texts(shown).contains("From the revision table"))
        #expect(!(try shown.window.elements(role: .textField).contains { $0.value == "C" }), "the typed value is kept, not shown")
    }
}
