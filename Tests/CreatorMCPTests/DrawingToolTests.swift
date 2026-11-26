import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorMCP

/// `list_drawings`, `get_sheet` and `export_drawing` over a `DocumentModelSession` with hooks (DR-5 R19).
@MainActor struct DrawingToolTests {
    struct ExportCall: Equatable {
        var kind: String
        var sheet: SheetID?
        var view: ViewID?
        var url: URL
        var overwrite: Bool
    }

    final class Calls { var exports: [ExportCall] = [] }

    /// A fixture with two sheets: "Plate" holds a base view and an assembly view of two parts; "Spare" is empty.
    struct Fixture {
        let base: SessionFixture
        let plate: SheetID
        let spare: SheetID
        let baseView: ViewID
        let assemblyView: ViewID
        let parts: [NodeID]
        let lost: AnnotationID
        let balloon: AnnotationID
        let calls = Calls()
    }

    func fixture(statuses: [Int: ViewStatus] = [:]) async throws -> Fixture {
        let base = try await SessionFixture()
        let registry = base.document.registry
        let second = registry.makeNode("creator.output")
        try base.document.perform(.addNode(second), name: "Add Output")
        let parts = [base.output, second.id]
        let baseView = DrawingView(kind: .base, source: parts[0], orientation: .standard(.front), center: Vector2(100, 100))
        let assembly = DrawingView(
            kind: .projected, source: parts[0], orientation: .standard(.top), scale: DrawingScale(numerator: 1, denominator: 2),
            center: Vector2(200, 100), letter: "B", assembly: parts)
        let lost = DrawingAnnotation(
            view: baseView.id, kind: .note(DrawingNote(text: "Check", position: Vector2(5, 5))))
        let balloon = DrawingAnnotation(
            view: assembly.id,
            kind: .balloon(Balloon(leader: LeaderEnd(target: .point(Vector2(1, 1)), hint: .zero), offset: Vector2(10, 10))))
        let revisions = DrawingAnnotation(
            view: nil, kind: .revisionTable(RevisionTable(rows: [
                RevisionRow(letter: "A", description: "First issue", date: "2026-11-01", approved: "MB"),
            ])))
        let plate = DrawingSheet(
            name: "Plate", views: [baseView, assembly], annotations: [lost, balloon, revisions])
        let spare = DrawingSheet(name: "Spare", size: .a4, orientation: .portrait)
        var document = base.document.graph.drawings
        document.sheets = [plate, spare]
        document.items = [PartItem(part: parts[1], material: "Steel", partNumber: "P-2")]
        try base.document.perform(.setDrawings(document), name: "Add Sheets")
        return Fixture(base: base, plate: plate.id, spare: spare.id, baseView: baseView.id, assemblyView: assembly.id,
                       parts: parts, lost: lost.id, balloon: balloon.id)
    }

    func hook(_ fixture: Fixture, views: [ViewID: ViewStatus]? = nil) {
        let session = fixture.base.session
        let reports: [AnnotationID: AnnotationReport] = [
            fixture.lost: AnnotationReport(status: .lost(.missing), label: "Check?"),
            fixture.balloon: AnnotationReport(status: .held, label: "1", warnings: ["Too close."]),
        ]
        let statuses = views ?? [fixture.baseView: .drawn, fixture.assemblyView: .drawn]
        let facts = TitleBlockFacts(parts: [
            fixture.parts[0]: PartFacts(name: "Plate part", quantity: 2, isRemoved: false),
            fixture.parts[1]: PartFacts(name: "Bracket", quantity: nil, isRemoved: false),
        ])
        session.drawingSheetProvider = { id in
            guard id == fixture.plate else { return nil }
            return DrawingSheetSnapshot(
                picture: SheetPicture(size: Vector2(420, 297), annotationReports: reports), facts: facts, views: statuses)
        }
        let calls = fixture.calls
        session.drawingExporter = { kind, sheet, view, url, overwrite in
            calls.exports.append(ExportCall(kind: kind, sheet: sheet, view: view, url: url, overwrite: overwrite))
            return .done("Exported \(url.lastPathComponent).")
        }
    }

    @Test func listDrawingsDescribesSheetsAndViews() async throws {
        let f = try await fixture()
        let (result, isError) = try await f.base.call("list_drawings")
        #expect(!isError)
        #expect(result["standard"]?.string == "iso")
        let sheets = try #require(result["sheets"]?.array)
        #expect(sheets.count == 2)
        let plate = sheets[0]
        #expect(plate["id"]?.string == f.plate.rawValue.uuidString)
        #expect(plate["name"]?.string == "Plate" && plate["size"]?.string == "A3")
        #expect(plate["orientation"]?.string == "landscape" && plate["scale"]?.string == "1 : 1")
        #expect(plate["revision"]?.string == "A" && plate["annotations"]?.int == 3)
        let views = try #require(plate["views"]?.array)
        #expect(views.count == 2)
        let assembly = try #require(views.first { $0["id"]?.string == f.assemblyView.rawValue.uuidString })
        #expect(assembly["kind"]?.string == "projected" && assembly["letter"]?.string == "B")
        #expect(assembly["orientation"]?.string == "Top" && assembly["scale"]?.string == "1 : 2")
        let parts = try #require(assembly["parts"]?.array)
        #expect(parts.count == 2)
        #expect(parts[0]["node"]?.string == f.parts[0].rawValue.uuidString)
        #expect(parts[0]["name"]?.string == f.base.document.graph.nodes[f.parts[0]]?.name)
        let plain = try #require(views.first { $0["id"]?.string == f.baseView.rawValue.uuidString })
        #expect(plain["letter"] == nil && plain["orientation"]?.string == "Front" && plain["scale"]?.string == "1 : 1")
        #expect(sheets[1]["size"]?.string == "A4" && sheets[1]["orientation"]?.string == "portrait")
        #expect(sheets[1]["views"]?.array?.isEmpty == true)
    }

    @Test func getSheetListsLostAnnotations() async throws {
        let f = try await fixture()
        hook(f)
        let (result, isError) = try await f.base.call("get_sheet", .object(["sheet": .string("Plate")]))
        #expect(!isError)
        #expect(result["complete"]?.bool == true)
        let annotations = try #require(result["annotations"]?.array)
        #expect(annotations.count == 3)
        let note = try #require(annotations.first { $0["id"]?.string == f.lost.rawValue.uuidString })
        #expect(note["status"]?.string == "lost" && note["kind"]?.string == "note" && note["label"]?.string == "Check?")
        #expect(note["reason"]?.string == LostReason.missing.sentence)
        #expect(note["view"]?.string == f.baseView.rawValue.uuidString)
        let held = try #require(annotations.first { $0["id"]?.string == f.balloon.rawValue.uuidString })
        #expect(held["status"]?.string == "held" && held["kind"]?.string == "balloon" && held["reason"] == nil)
        #expect(held["warnings"]?.array?.first?.string == "Too close.")
    }

    @Test func getSheetListsItemsAndRevisions() async throws {
        let f = try await fixture()
        hook(f)
        let (result, _) = try await f.base.call("get_sheet", .object(["sheet": .string(f.plate.rawValue.uuidString)]))
        #expect(result["sheet"]?["name"]?.string == "Plate")
        let items = try #require(result["parts_list"]?.array)
        #expect(items.count == 2)
        #expect(items[0]["item"]?.int == 1 && items[0]["name"]?.string == "Bracket" && items[0]["material"]?.string == "Steel")
        #expect(items[0]["part_number"]?.string == "P-2" && items[0]["quantity"] == .null)
        #expect(items[1]["item"]?.int == 2 && items[1]["quantity"]?.int == 2)
        let revisions = try #require(result["revisions"]?.array)
        let expected = JSONValue.object([
            "letter": .string("A"), "description": .string("First issue"), "date": .string("2026-11-01"), "approved": .string("MB"),
        ])
        #expect(revisions == [expected])
        let views = try #require(result["views"]?.array)
        #expect(views.allSatisfy { $0["status"]?.string == "drawn" })
    }

    @Test func aPendingViewIsReported() async throws {
        let f = try await fixture()
        hook(f)
        let session = f.base.session
        session.drawingSheetProvider = { [provider = session.drawingSheetProvider] id in
            guard var snapshot = await provider?(id) else { return nil }
            snapshot.views[f.assemblyView] = .pending
            snapshot.views[f.baseView] = .failed("It has no lines.")
            return snapshot
        }
        let (result, _) = try await f.base.call("get_sheet", .object(["sheet": .string("Plate")]))
        #expect(result["complete"]?.bool == false)
        let views = try #require(result["views"]?.array)
        let pending = try #require(views.first { $0["id"]?.string == f.assemblyView.rawValue.uuidString })
        #expect(pending["status"]?.string == "pending" && pending["problem"] == nil)
        let failed = try #require(views.first { $0["id"]?.string == f.baseView.rawValue.uuidString })
        #expect(failed["status"]?.string == "failed" && failed["problem"]?.string == "It has no lines.")
        #expect(result["annotations"]?.array?.count == 3, "the annotations as the snapshot judged them")
    }

    @Test func sheetsByNameOrID() async throws {
        let f = try await fixture()
        hook(f)
        func refusal(_ ref: JSONValue?) async throws -> String? {
            var arguments: [String: JSONValue] = [:]
            if let ref { arguments["sheet"] = ref }
            let (result, isError) = try await f.base.call("get_sheet", .object(arguments))
            return isError ? result.string : nil
        }
        #expect(try await refusal(nil) == "Say which sheet, by its ID or name.")
        let unknown = UUID().uuidString
        #expect(try await refusal(.string(unknown)) == "There's no sheet with ID \(unknown).")
        #expect(try await refusal(.string("Nope")) == "There's no sheet called “Nope”.")
        var document = f.base.document.graph.drawings
        document.sheets[1].name = "Plate"
        try f.base.document.perform(.setDrawings(document), name: "Rename")
        #expect(try await refusal(.string("Plate")) == "Two sheets are called “Plate”; use the sheet's ID.")
        #expect(try await refusal(.string(f.plate.rawValue.uuidString)) == nil)
        let view = DrawingAddressing.view(.string(UUID().uuidString), on: document.sheets[0])
        guard case .failure(let problem) = view else { Issue.record("expected a refusal"); return }
        #expect(problem.sentence.hasPrefix("There's no view with ID ") && problem.sentence.hasSuffix(" on “Plate”."))
    }

    @Test func exportDrawingChecksItsArguments() async throws {
        let f = try await fixture()
        hook(f)
        let path = absoluteTestPath("sheet.pdf")
        func run(_ arguments: [String: JSONValue]) async throws -> String? {
            let (result, isError) = try await f.base.call("export_drawing", .object(arguments))
            return isError ? result.string : nil
        }
        let kinds = "Drawing export kinds are pdf, pdf_sheet, dxf_sheet, dxf_view, dxf_view_annotations and svg_sheet."
        #expect(try await run(["kind": .string("png"), "path": .string(path)]) == kinds)
        #expect(try await run(["kind": .string("pdf_sheet"), "path": .string(path)]) == "Say which sheet to export.")
        let noView = try await run(["kind": .string("dxf_view"), "sheet": .string("Plate"), "path": .string(path)])
        #expect(noView == "Say which view to export.")
        #expect(try await run(["kind": .string("pdf"), "path": .string("relative.pdf")]) == "Paths must be absolute.")
        #expect(try await run(["kind": .string("pdf")]) == "Say which file, by its absolute path.")
        #expect(f.calls.exports.isEmpty)
    }

    @Test func exportDrawingPassesThrough() async throws {
        let f = try await fixture()
        hook(f)
        let path = absoluteTestPath("view.dxf")
        let (result, isError) = try await f.base.call("export_drawing", .object([
            "kind": .string("dxf_view_annotations"), "sheet": .string("Plate"), "view": .string(f.assemblyView.rawValue.uuidString),
            "path": .string(path), "overwrite": .bool(true),
        ]))
        #expect(!isError && result["done"]?.bool == true && result["message"]?.string == "Exported view.dxf.")
        #expect(f.calls.exports == [ExportCall(
            kind: "dxf_view_annotations", sheet: f.plate, view: f.assemblyView, url: URL(fileURLWithPath: path), overwrite: true),
        ])
        _ = try await f.base.call("export_drawing", .object(["kind": .string("pdf"), "path": .string(path)]))
        #expect(f.calls.exports.last == ExportCall(kind: "pdf", sheet: nil, view: nil, url: URL(fileURLWithPath: path), overwrite: false))
    }

    @Test func withoutHooksDrawingsAreRefused() async throws {
        let f = try await fixture()
        let (read, readError) = try await f.base.call("get_sheet", .object(["sheet": .string("Plate")]))
        #expect(readError && read.string == "Drawings can't be read from this session.")
        let (written, writeError) = try await f.base.call(
            "export_drawing", .object(["kind": .string("pdf"), "path": .string(absoluteTestPath("x.pdf"))]))
        #expect(writeError && written.string == "Drawings can't be exported from this session.")
        let (listed, listError) = try await f.base.call("list_drawings")
        #expect(!listError && listed["sheets"]?.array?.count == 2, "listing reads the document alone")
    }
}
