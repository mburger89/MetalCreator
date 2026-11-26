import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The revision table's rows (DR-5 R8, R9, R16).
@MainActor
@Suite("Revision model")
struct RevisionModelTests {
    private func open(table: Bool = true, rows: [RevisionRow] = []) -> EditorHarness {
        var annotations: [DrawingAnnotation] = []
        if table { annotations.append(DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(rows: rows)))) }
        let sheet = DrawingSheet(name: "Sheet 1", annotations: annotations)
        return EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
    }

    private func rows(_ h: EditorHarness) -> [RevisionRow] {
        h.model.document.sheets[0].revisionTable?.table.rows ?? []
    }

    @Test func aNewRevisionHasNoDate() throws {
        let h = open()
        h.model.addRevision()
        #expect(rows(h) == [RevisionRow(letter: "A")])
        h.model.addRevision()
        #expect(rows(h).map(\.letter) == ["A", "B"])
        #expect(rows(h)[1].date.isEmpty && rows(h)[1].description.isEmpty && rows(h)[1].approved.isEmpty)
        #expect(h.log.commits.map(\.name) == ["Add Revision", "Add Revision"])
    }

    @Test func revisionsSkipTheStandardsLetters() throws {
        let h = open(rows: [RevisionRow(letter: "H")])
        h.model.addRevision()
        #expect(rows(h).last?.letter == "J")
        let g = open(rows: [RevisionRow(letter: "N")])
        g.model.addRevision()
        #expect(rows(g).last?.letter == "P")
    }

    @Test func typedFieldsAreStored() throws {
        let h = open(rows: [RevisionRow(letter: "A")])
        h.model.setRevision(.description, text: "First issue", row: 0)
        h.model.setRevision(.date, text: "2026-11-26", row: 0)
        h.model.setRevision(.approved, text: "MB", row: 0)
        #expect(rows(h)[0] == RevisionRow(letter: "A", description: "First issue", date: "2026-11-26", approved: "MB"))
        #expect(h.log.commits.map(\.name) == ["Change Revision", "Change Revision", "Change Revision"])
        h.model.setRevision(.approved, text: "MB", row: 0)
        h.model.setRevision(.approved, text: "x", row: 5)
        #expect(h.log.commits.count == 3)
    }

    @Test func onlyTheLastIsRemoved() throws {
        let h = open(rows: [RevisionRow(letter: "A"), RevisionRow(letter: "B")])
        h.model.removeLastRevision()
        #expect(rows(h).map(\.letter) == ["A"])
        #expect(h.log.commits.map(\.name) == ["Remove Revision"])
        h.model.removeLastRevision()
        h.model.removeLastRevision()
        #expect(h.log.commits.count == 2)
    }

    @Test func withoutATableAddRevisionRefuses() throws {
        let h = open(table: false)
        h.model.addRevision()
        #expect(h.model.refusal == "Add a revision table first.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func theTitleBlockRevisionIsRefusedWhileTheTableHasRows() throws {
        let h = open(rows: [RevisionRow(letter: "A")])
        h.model.setTitleField(.revision, to: "C")
        #expect(h.model.refusal == "The revision comes from the revision table.")
        #expect(h.log.commits.isEmpty)
        let empty = open()
        empty.model.setTitleField(.revision, to: "C")
        #expect(empty.log.commits.count == 1)
    }
}
