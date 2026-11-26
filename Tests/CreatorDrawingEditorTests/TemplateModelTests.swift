import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// New sheets from templates, logos and the host's requests (DR-5 R10, R16).
@MainActor
@Suite("Template model")
struct TemplateModelTests {
    private let hash = String(repeating: "ab", count: 32)

    private func template(standard: DrawingStandard = .iso) -> DrawingTemplate {
        DrawingTemplate(
            id: "t1", name: "Acme", size: .a2, orientation: .portrait, standard: standard,
            titleBlock: TitleBlock(owner: "Acme", title: "ignored", material: "S235", drawnBy: "MB", density: 7.85))
    }

    @Test func aSheetFromATemplate() throws {
        let existing = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([existing]), sheet: existing.id)
        h.model.addSheet(from: template(), logo: hash)
        #expect(h.log.commits.map(\.name) == ["Add Sheet"])
        let sheet = try #require(h.model.document.sheets.last)
        #expect(sheet.name == "Sheet 2")
        #expect(sheet.size == .a2)
        #expect(sheet.orientation == .portrait)
        #expect(sheet.titleBlock.owner == "Acme")
        #expect(sheet.titleBlock.drawnBy == "MB")
        #expect(sheet.titleBlock.material == "S235")
        #expect(sheet.titleBlock.density == 7.85)
        #expect(sheet.titleBlock.logo == hash)
        #expect(sheet.titleBlock.title.isEmpty)
        #expect(sheet.titleBlock.date == "2026-11-24")
        #expect(h.model.currentSheet == sheet.id)
    }

    @Test func theStandardOnlyOnTheFirstSheet() throws {
        let empty = EditorHarness(document: DrawingDocument(), sheet: nil)
        empty.model.addSheet(from: template(standard: .asme), logo: nil)
        #expect(empty.model.document.settings.standard == .asme)
        let existing = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([existing]), sheet: existing.id)
        h.model.addSheet(from: template(standard: .asme), logo: nil)
        #expect(h.model.document.settings.standard == .iso)
    }

    @Test func requestsReachTheHost() throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        var requests: [DrawingEditorRequest] = []
        let model = DrawingEditorModel(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, today: { "2026-11-24" },
            events: DrawingEditorEvents(committed: { _ in }, requested: { requests.append($0) }))
        let all: [DrawingEditorRequest] = [
            .saveSheetAsTemplate(sheet.id), .chooseLogo(sheet.id), .renameTemplate("t1", to: "New"), .deleteTemplate("t1"),
            .newSheetFromTemplate("t1"),
        ]
        for request in all { model.request(request) }
        #expect(requests == all)
    }

    @Test func settingALogo() throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.setLogo(hash, of: sheet.id)
        #expect(h.model.document.sheets[0].titleBlock.logo == hash)
        h.model.setLogo(hash, of: sheet.id)
        #expect(h.log.commits.count == 1)
        h.model.setLogo(nil, of: sheet.id)
        #expect(h.model.document.sheets[0].titleBlock.logo == nil)
        #expect(h.log.commits.map(\.name) == ["Change Logo", "Change Logo"])
    }
}
