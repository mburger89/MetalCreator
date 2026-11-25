import CreatorDrawing
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// The drawings are saved with the top-level graph (DR-1 Task 4): format 17, the key written only when there is a sheet, one command
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

    @Test func theFormatIs17() {
        #expect(GraphFile.currentFormatVersion == 17)
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
        #expect(back.formatVersion == 17)
    }

    @Test func aFormat16FileOpens() throws {
        let text = #"{"formatVersion": 16, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 16)
        #expect(file.graph.drawings.isEmpty)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 17)
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
