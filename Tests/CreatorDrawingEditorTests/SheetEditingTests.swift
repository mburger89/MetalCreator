import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

@MainActor
@Suite("Sheet editing")
struct SheetEditingTests {
    @Test func addSheetNamesAndDatesIt() throws {
        let h = EditorHarness(document: DrawingDocument(), sheet: nil)
        h.model.addSheet()
        #expect(h.log.commits.count == 1)
        #expect(h.log.commits[0].name == "Add Sheet")
        let sheet = try #require(h.model.document.sheets.first)
        #expect(sheet.name == "Sheet 1")
        #expect(sheet.size == .a3)
        #expect(sheet.orientation == .landscape)
        #expect(sheet.titleBlock.date == "2026-11-24")
        #expect(h.model.currentSheet == sheet.id)
        #expect(h.log.sheets.last == sheet.id)
    }

    @Test func theSmallestUnusedNumber() throws {
        let h = EditorHarness(document: DrawingDocument(), sheet: nil)
        h.model.addSheet()
        h.model.addSheet()
        #expect(h.model.document.sheets.map(\.name) == ["Sheet 1", "Sheet 2"])
        h.model.deleteSheet(h.model.document.sheets[0].id)
        h.model.addSheet()
        #expect(h.model.document.sheets.map(\.name).sorted() == ["Sheet 1", "Sheet 2"])
    }

    @Test func aNewASMESheetIsANSIB() throws {
        let h = EditorHarness(
            document: DrawingDocument(settings: DrawingSettings(standard: .asme)), sheet: nil)
        h.model.addSheet()
        let sheet = try #require(h.model.document.sheets.first)
        #expect(sheet.size == .ansiB)
        #expect(sheet.orientation == .landscape)
    }

    @Test func aNewSheetStartsFromTheTitleDefaults() throws {
        var settings = DrawingSettings()
        settings.titleBlockDefaults = TitleBlock(owner: "Acme", drawnBy: "MB")
        let h = EditorHarness(document: DrawingDocument(settings: settings), sheet: nil)
        h.model.addSheet()
        let block = try #require(h.model.document.sheets.first).titleBlock
        #expect(block.owner == "Acme")
        #expect(block.drawnBy == "MB")
    }

    @Test func renameIsOneStep() throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.renameSheet(sheet.id, to: "Plate")
        #expect(h.log.commits.map(\.name) == ["Rename Sheet"])
        #expect(h.model.document.sheets[0].name == "Plate")
    }

    @Test func duplicateCopiesViewsWithNewIDs() throws {
        let parent = EditorDocuments.view(at: Vector2(100, 150))
        let child = EditorDocuments.child(of: parent, axis: .horizontal, at: Vector2(200, 150))
        let sheet = DrawingSheet(name: "Sheet 1", views: [parent, child])
        let other = DrawingSheet(name: "Sheet 2")
        let h = EditorHarness(document: EditorDocuments.document([sheet, other]), sheet: sheet.id)
        h.model.duplicateSheet(sheet.id)
        #expect(h.log.commits.map(\.name) == ["Duplicate Sheet"])
        let sheets = h.model.document.sheets
        #expect(sheets.count == 3)
        #expect(sheets[2].id == other.id)
        let copy = sheets[1]
        #expect(copy.id != sheet.id)
        #expect(copy.views.count == 2)
        #expect(Set(copy.views.map(\.id)).isDisjoint(with: [parent.id, child.id]))
        let copiedChild = try #require(copy.views.first { $0.kind == .projected })
        let copiedParent = try #require(copy.views.first { $0.kind == .base })
        #expect(copiedChild.alignment == ViewAlignment(parent: copiedParent.id, axis: .horizontal))
        #expect(h.model.currentSheet == copy.id)
    }

    @Test func deleteSelectsTheNeighbour() throws {
        let sheets = ["a", "b", "c"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[1].id)
        h.model.deleteSheet(sheets[1].id)
        #expect(h.log.commits.map(\.name) == ["Delete Sheet"])
        #expect(h.model.currentSheet == sheets[2].id)
        h.model.deleteSheet(sheets[2].id)
        #expect(h.model.currentSheet == sheets[0].id)
        h.model.deleteSheet(sheets[0].id)
        #expect(h.model.currentSheet == nil)
        #expect(h.log.sheets.last == .some(nil))
    }

    @Test func moveSheetReorders() throws {
        let sheets = ["a", "b", "c"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.moveSheet(sheets[0].id, by: 1)
        #expect(h.model.document.sheets.map(\.name) == ["b", "a", "c"])
        h.model.moveSheet(sheets[0].id, by: 5)
        #expect(h.model.document.sheets.map(\.name) == ["b", "c", "a"])
        #expect(h.log.commits.map(\.name) == ["Move Sheet", "Move Sheet"])
    }

    @Test func editingATitleFieldUpdatesTheDefaults() throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.setTitleField(.title, to: "Bracket")
        #expect(h.log.commits.count == 1)
        #expect(h.log.commits[0].name == "Edit Title Block")
        #expect(h.model.document.sheets[0].titleBlock.title == "Bracket")
        #expect(h.model.document.settings.titleBlockDefaults.title == "Bracket")
        let commits = h.log.commits.count
        h.model.setTitleField(.tolerance, to: "ISO 2768-fH")
        #expect(h.log.commits.count == commits)
        #expect(h.model.document.settings.generalTolerance == .iso2768(.m, .K))
    }

    @Test func addSheetFillsAnEmptyTolerance() throws {
        var empty = DrawingDocument()
        empty.settings.generalTolerance = .text("")
        let h = EditorHarness(document: empty, sheet: nil)
        h.model.addSheet()
        #expect(h.model.document.settings.generalTolerance == .standardDefault(for: .iso, inches: false))
        var typed = DrawingDocument()
        typed.settings.generalTolerance = .text("Per drawing 12")
        let kept = EditorHarness(document: typed, sheet: nil)
        kept.model.addSheet()
        #expect(kept.model.document.settings.generalTolerance == .text("Per drawing 12"))
    }

    @Test func changeStandardIsOneStep() throws {
        func sheet(_ name: String) -> (DrawingSheet, ViewID) {
            let parent = EditorDocuments.view(at: Vector2(100, 150))
            let child = EditorDocuments.child(of: parent, axis: .horizontal, at: Vector2(180, 150))
            return (DrawingSheet(name: name, views: [parent, child]), child.id)
        }
        let (first, firstChild) = sheet("one")
        let (second, secondChild) = sheet("two")
        let h = EditorHarness(document: EditorDocuments.document([first, second]), sheet: first.id)
        h.model.setStandard(.asme)
        #expect(h.log.commits.map(\.name) == ["Change Standard"])
        #expect(h.model.document.settings.standard == .asme)
        for (index, id) in [firstChild, secondChild].enumerated() {
            let moved = try #require(h.model.document.sheets[index].view(id))
            #expect(abs(moved.center.x - 20) < 1e-9)
        }
    }

    @Test func sheetChangeIsNotACommit() throws {
        let sheets = ["a", "b"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.selectSheet(sheets[1].id)
        #expect(h.log.commits.isEmpty)
        #expect(h.model.currentSheet == sheets[1].id)
        #expect(h.log.sheets.last == sheets[1].id)
    }
}
