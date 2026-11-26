import CreatorGeometry
import Testing

@testable import CreatorDrawing

/// The revision table (DR-5 Task 5, R9).
@Suite("Revision table layout")
struct RevisionTableLayoutTests {
    private let top = Vector2(280, 200)
    private var table: RevisionTable {
        RevisionTable(rows: [
            RevisionRow(letter: "A", description: "First", date: "2026-01-02", approved: "MB"),
            RevisionRow(letter: "B", description: "Second"),
        ])
    }

    @Test func theHeaderIsAtTheTop() {
        let drawing = RevisionTableLayout.draw(table, topRight: top, standard: .iso, h: 2.5)
        #expect(drawing.texts.prefix(drawing.labelCount).map(\.original) == ["Rev.", "Description", "Date", "Approved"])
        let header = drawing.texts[0].origin.y
        let first = drawing.texts.first { $0.original == "First" }!.origin.y
        let second = drawing.texts.first { $0.original == "Second" }!.origin.y
        #expect(abs(header - first - 7) < 1e-9 && abs(first - second - 7) < 1e-9, "oldest first, below the header")
        #expect(abs(drawing.frame.max.y - top.y) < 1e-9 && abs(drawing.frame.max.x - top.x) < 1e-9)
        #expect(abs(drawing.frame.height - 21) < 1e-9 && abs(drawing.frame.width - 180) < 1e-9)
    }

    @Test func columnsAndLabels() {
        let iso = RevisionTableLayout.columns(for: .iso)
        #expect(iso.map(\.width) == [15, 100, 30, 35] && iso.map(\.title) == ["Rev.", "Description", "Date", "Approved"])
        let asme = RevisionTableLayout.columns(for: .asme)
        #expect(asme.map(\.title) == ["REV", "DESCRIPTION", "DATE", "APPROVED"] && asme.map(\.width) == [15, 100, 30, 35])
    }

    @Test func typedTextIsFitted() {
        let long = String(repeating: "Longer ", count: 40)
        let drawing = RevisionTableLayout.draw(
            RevisionTable(rows: [RevisionRow(letter: "A", description: long)]), topRight: top, standard: .iso, h: 2.5)
        let text = drawing.texts.first { $0.original == long }
        #expect(text != nil && (text?.run.width ?? 1000) <= 97 + 1e-9)
    }
}
