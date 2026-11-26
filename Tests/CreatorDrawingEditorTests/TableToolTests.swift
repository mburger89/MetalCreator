import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Parts List and Revision Table tools (DR-5 R7, R9, R16).
@MainActor
@Suite("Table tools")
struct TableToolTests {
    private func open(_ annotations: [DrawingAnnotation] = [], standard: DrawingStandard = .iso) -> (EditorHarness, DrawingSheet) {
        var sheet = DrawingSheet(name: "Sheet 1", annotations: annotations)
        sheet.size = .a3
        let h = EditorHarness(
            document: EditorDocuments.document([sheet], settings: DrawingSettings(standard: standard)), sheet: sheet.id)
        return (h, sheet)
    }

    private func blockTopRight(_ sheet: DrawingSheet, _ standard: DrawingStandard = .iso) -> Vector2 {
        let origin = TitleBlockLayout.origin(for: sheet, standard: standard)
        return Vector2(origin.x + TitleBlockLayout.width, origin.y + TitleBlockLayout.height)
    }

    private func partsList(_ h: EditorHarness) -> PartsList? {
        for annotation in h.model.document.sheets[0].annotations {
            if case .partsList(let list) = annotation.kind { return list }
        }
        return nil
    }

    private func revisionTable(_ h: EditorHarness) -> RevisionTable? {
        for annotation in h.model.document.sheets[0].annotations {
            if case .revisionTable(let table) = annotation.kind { return table }
        }
        return nil
    }

    @Test func aPartsListStandsOnTheBlockNearIt() throws {
        let (h, sheet) = open()
        let corner = blockTopRight(sheet)
        h.model.press(.partsList)
        h.click(corner.x - 4, corner.y + 4.5)
        #expect(h.log.commits.map(\.name) == ["Add Parts List"])
        let list = try #require(partsList(h))
        #expect(list.bottomRight == nil)
        #expect(h.model.selectedAnnotations.count == 1)
    }

    @Test func aPartsListElsewhereIsFree() throws {
        let (h, _) = open()
        h.model.press(.partsList)
        h.click(200, 100)
        #expect(partsList(h)?.bottomRight == Vector2(200, 100))
    }

    @Test func aSecondPartsListIsRefused() throws {
        let (h, _) = open([DrawingAnnotation(view: nil, kind: .partsList(PartsList()))])
        h.model.press(.partsList)
        h.click(200, 100)
        #expect(h.model.refusal == "This sheet has a parts list already; drag it to move it.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func aRevisionTableSnapsToTheCorner() throws {
        let (h, sheet) = open()
        let corner = SheetFrame.rect(for: sheet, standard: .iso).max
        h.model.press(.revisionTable)
        h.click(corner.x - 6, corner.y - 5)
        #expect(h.log.commits.map(\.name) == ["Add Revision Table"])
        #expect(revisionTable(h)?.topRight == nil)
    }

    @Test func aRevisionTableElsewhereIsFree() throws {
        let (h, _) = open()
        h.model.press(.revisionTable)
        h.click(250, 150)
        #expect(revisionTable(h)?.topRight == Vector2(250, 150))
    }

    @Test func aSecondRevisionTableIsRefused() throws {
        let (h, _) = open([DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable()))])
        h.model.press(.revisionTable)
        h.click(250, 150)
        #expect(h.model.refusal == "This sheet has a revision table already; drag it to move it.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func draggingAStandingListFreesIt() throws {
        let (h, sheet) = open([DrawingAnnotation(view: nil, kind: .partsList(PartsList()))])
        let id = h.model.document.sheets[0].annotations[0].id
        let frame = try #require(h.model.picture?.annotationReports[id]?.frame)
        let start = frame.center
        h.model.pointerDown(at: h.canvas(start.x, start.y), modifiers: [])
        h.model.pointerDragged(to: h.canvas(start.x - 10, start.y + 5))
        h.model.pointerDragged(to: h.canvas(start.x - 20, start.y + 10))
        h.model.pointerUp(at: h.canvas(start.x - 20, start.y + 10))
        #expect(!h.log.commits.isEmpty && h.log.commits.allSatisfy { $0.name == "Move Parts List" })
        let moved = try #require(partsList(h)?.bottomRight)
        let expected = blockTopRight(sheet) + Vector2(-20, 10)
        #expect((moved - expected).length < 1e-6, "\(moved) vs \(expected)")
    }

    @Test func nudgingARevisionTable() throws {
        let (h, sheet) = open([DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable()))])
        h.model.selectedAnnotations = [h.model.document.sheets[0].annotations[0].id]
        h.model.keyPressed(.nudge(Vector2(-1, 0), isRepeat: false))
        #expect(h.log.commits.map(\.name) == ["Move Revision Table"])
        let corner = SheetFrame.rect(for: sheet, standard: .iso).max
        #expect(revisionTable(h)?.topRight == corner + Vector2(-1, 0))
    }

    @Test func standingAgain() throws {
        let (h, _) = open([DrawingAnnotation(view: nil, kind: .partsList(PartsList(bottomRight: Vector2(200, 100))))])
        h.model.standPartsListOnTitleBlock()
        #expect(h.log.commits.map(\.name) == ["Move Parts List"])
        #expect(partsList(h)?.bottomRight == nil)
        h.model.standPartsListOnTitleBlock()
        #expect(h.log.commits.count == 1, "already standing")
        let (g, _) = open([DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable(topRight: Vector2(250, 150))))])
        g.model.moveRevisionTableToCorner()
        #expect(g.log.commits.map(\.name) == ["Move Revision Table"])
        #expect(revisionTable(g)?.topRight == nil)
    }

    @Test func deletingTables() throws {
        let (h, _) = open([
            DrawingAnnotation(view: nil, kind: .partsList(PartsList())),
            DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable())),
        ])
        let annotations = h.model.document.sheets[0].annotations
        let list = try #require(annotations.first { if case .partsList = $0.kind { true } else { false } })
        let table = try #require(annotations.first { if case .revisionTable = $0.kind { true } else { false } })
        h.model.selectedAnnotations = [list.id]
        h.model.deleteSelection()
        h.model.selectedAnnotations = [table.id]
        h.model.deleteSelection()
        #expect(h.log.commits.map(\.name) == ["Delete Parts List", "Delete Revision Table"])
    }
}
