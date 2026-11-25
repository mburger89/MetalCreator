import CreatorDrawing
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// The drawings are saved with the top-level graph (DR-1 Task 4): format 19, the key written only when there is a sheet, one command
/// that replaces the document, and the mode and sheet kept as view state.
@MainActor
struct DrawingsFileTests {
    private func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    private func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    private func drawings(_ names: String...) -> DrawingDocument {
        DrawingDocument(sheets: names.map { DrawingSheet(name: $0) })
    }

    private func emptyDocument() -> DocumentModel {
        DocumentModel(file: GraphFile(), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func theFormatIs19() {
        #expect(GraphFile.currentFormatVersion == 19)
    }

    @Test func aDocumentWithoutDrawingsHasNoKey() throws {
        let written = try #require(try json(GraphFile())["graph"] as? [String: Any])
        #expect(written["drawings"] == nil)
    }

    @Test func drawingsRoundTripThroughAFile() throws {
        let sheets = drawings("Plate", "Cover")
        let file = GraphFile(graph: Graph(drawings: sheets))
        let written = try #require(try json(file)["graph"] as? [String: Any])
        #expect(written["drawings"] != nil)
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets.map(\.name) == ["Plate", "Cover"])
        #expect(back.formatVersion == 19)
    }

    @Test func aFormat16FileOpens() throws {
        let text = #"{"formatVersion": 16, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 16)
        #expect(file.graph.drawings.isEmpty)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 19)
    }

    @Test func aFormat17FileOpensAndIsWrittenAs19() throws {
        let text = #"""
        {"formatVersion": 17, "graph": {"nodes": [], "links": [], "parameters": [],
         "drawings": {"settings": {"standard": "iso", "generalTolerance": "ISO 2768-mK", "titleBlockDefaults": {}}, "sheets": []}}}
        """#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 17)
        #expect(file.graph.drawings.settings.generalTolerance == .iso2768(.m, .K))
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 19)
    }

    @Test func aFormat18FileOpensAndIsWrittenAs19() throws {
        let text = #"""
        {"formatVersion": 18, "graph": {"nodes": [], "links": [], "parameters": [],
         "drawings": {"settings": {"standard": "iso", "generalTolerance": "ISO 2768-mK", "titleBlockDefaults": {}}, "sheets": []}}}
        """#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 18)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 19)
    }

    @Test func derivedViewsRoundTrip() throws {
        let node = NodeID()
        let base = DrawingView(kind: .base, source: node, orientation: .standard(.top), center: Vector2(100, 100))
        let cutter = SectionCutter(
            frame: base.orientation.frame, points: [Vector2(0, 0), Vector2(20, 0)], viewing: Vector2(0, 1))
        let section = DrawingView(
            kind: .section, source: node, orientation: .custom(SectionFrame.frame(for: cutter)), center: Vector2(100, 200),
            derivation: .section(SectionLine(parent: base.id, cutter: cutter)), letter: "A")
        let detail = DrawingView(
            kind: .detail, source: node, orientation: base.orientation, center: Vector2(200, 100),
            derivation: .detail(DetailCircle(parent: base.id, center: Vector2(5, 5), radius: 4)), letter: "B")
        let file = GraphFile(graph: Graph(drawings: DrawingDocument(sheets: [
            DrawingSheet(name: "Plate", views: [base, section, detail])])))
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets[0].views.count == 3)
    }

    @Test func aNewerFileIsRefused() throws {
        let text = #"{"formatVersion": 20, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        #expect(throws: (any Error).self) { try GraphFileIO.decode(Data(text.utf8), registry: testRegistry) }
    }

    @Test func annotationsRoundTripThroughTheGraphFile() throws {
        let node = NodeID()
        let view = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 100))
        let tag = TopoTag(node: node, item: 0, role: .startCap)
        let pick = EdgePick(key: EdgeKey([tag], [TopoTag(node: node, item: 0, role: .endCap)]), matchCount: 1)
        let annotation = DrawingAnnotation(
            id: AnnotationID(), view: view.id,
            kind: .dimension(
                DrawingDimension(
                    kind: .linear(.horizontal), anchors: [.edge(pick), .point(Vector2(1, 2))],
                    placement: DimensionPlacement(offset: 8, angle: 0, textShift: nil), tolerance: .symmetric(0.1))))
        var sheet = DrawingSheet(name: "Plate", views: [view])
        sheet.setAnnotation(annotation)
        var document = DrawingDocument(sheets: [sheet])
        document.settings.decimalSign = .comma
        let file = GraphFile(graph: Graph(drawings: document))
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets[0].annotations == [annotation])
        #expect(back.graph.drawings.settings.decimalSign == .comma)
    }

    @Test func setDrawingsIsUndoable() throws {
        let document = emptyDocument()
        let one = drawings("Sheet 1")
        try document.perform(.setDrawings(one), name: UndoName.drawing("Add Sheet"))
        #expect(document.drawings == one)
        #expect(document.undoName == "Add Sheet")
        document.undo()
        #expect(document.drawings.isEmpty)
        #expect(document.redoName == "Add Sheet")
        document.redo()
        #expect(document.drawings == one)
    }

    @Test func setDrawingsDoesNotEvaluate() async throws {
        let command = GraphCommand.setDrawings(drawings("A"))
        #expect(command.affectsResults == false)
        #expect(command.touchedNodes.isEmpty)
        let document = emptyDocument()
        await document.waitForEvaluation()
        try document.perform(command, name: UndoName.drawing("Add Sheet"))
        #expect(!document.isEvaluating, "no evaluation was scheduled")
    }

    @Test func drawingsMakeTheDocumentEdited() throws {
        let document = emptyDocument()
        let saved = document.content
        try document.perform(.setDrawings(drawings("A")), name: UndoName.drawing("Add Sheet"))
        #expect(document.content != saved)
    }

    @Test func setDrawingsInsideADefinitionIsRefused() throws {
        let definition = Doubler().definition
        let document = DocumentModel(file: GraphFile(graph: graph([]), definitions: table([definition])), registry: testRegistry,
                                     kernel: FakeKernel())
        #expect(throws: GraphError.invalidValue("Drawings belong to the document, not to a group.")) {
            try document.perform(.setDrawings(drawings("A")), at: .definition(definition.id), name: UndoName.drawing("Add Sheet"))
        }
        #expect(document.drawings.isEmpty)
    }

    @Test func drawingViewStateRoundTrips() throws {
        let sheet = SheetID()
        for state in [DrawingViewState(isOn: true, sheet: sheet), DrawingViewState(isOn: false, sheet: nil)] {
            let view = ViewState(drawing: state)
            #expect(try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(view)) == view)
        }
        let none = try #require(String(bytes: JSONEncoder().encode(ViewState()), encoding: .utf8))
        #expect(!none.contains("\"drawing\""))
        let damaged = try JSONDecoder().decode(ViewState.self, from: Data(#"{"drawing":{"isOn":"yes"}}"#.utf8))
        #expect(damaged.drawing == nil)
        let file = GraphFile(viewState: ViewState(drawing: DrawingViewState(isOn: true, sheet: sheet)))
        #expect(try reopened(file).viewState.drawing == DrawingViewState(isOn: true, sheet: sheet))
    }

    @Test func drawingViewIsNotAnEdit() {
        let document = emptyDocument()
        let before = document.content
        let undoName = document.undoName
        document.drawingView = DrawingViewState(isOn: true, sheet: SheetID())
        #expect(document.content == before)
        #expect(document.undoName == undoName)
        #expect(document.viewState.drawing == document.drawingView)
        document.viewState = ViewState()
        #expect(document.drawingView == nil)
    }

    @Test func aBlankNameIsEditDrawing() {
        #expect(UndoName.drawing("  ") == "Edit Drawing")
        #expect(UndoName.drawing("") == UndoName.editDrawing)
        #expect(UndoName.drawing("Add Sheet") == "Add Sheet")
    }
}
