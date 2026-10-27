import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// The document's units are saved with its graph (DIM-1 Task 4): format 10, the key written only when the units are not
/// the default millimetres, and a file without it reads millimetres. Changing them is one undoable step that changes no result.
@MainActor
struct DocumentUnitsFileTests {
    func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    @Test func aFileWithoutUnitsReadsMillimetres() throws {
        let text = #"{"formatVersion": 9, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.units == .millimetres)
    }

    @Test func unitsRoundTrip() throws {
        var graph = Graph()
        graph.units = DocumentUnits(length: .inches, precision: 3)
        let file = GraphFile(graph: graph)
        let written = try #require(try json(file)["graph"] as? [String: Any])
        let units = try #require(written["units"] as? [String: Any])
        #expect(units["length"] as? String == "in" && units["precision"] as? Int == 3)
        #expect(try reopened(file) == file)
        #expect(try reopened(file).graph.units == DocumentUnits(length: .inches, precision: 3))
    }

    @Test func millimetresAtTheirDefaultPrecisionWriteNoKey() throws {
        let written = try #require(try json(GraphFile())["graph"] as? [String: Any])
        #expect(written["units"] == nil)
    }

    @Test func theFormatIsTenAndNineStillOpens() throws {
        #expect(GraphFile.currentFormatVersion == 10, "10: document units")
        let text = #"{"formatVersion": 9, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 9)
        let saved = try reopened(GraphFile(graph: file.graph, definitions: file.definitions, viewState: file.viewState))
        #expect(saved.formatVersion == 10)
    }

    @Test func setUnitsIsOneUndoStepThatChangesNoResult() {
        let document = DocumentModel(file: GraphFile(), registry: testRegistry, kernel: FakeKernel())
        #expect(document.units == .millimetres)
        #expect(GraphCommand.setUnits(.millimetres).affectsResults == false)
        #expect(GraphCommand.setUnits(.millimetres).touchedNodes.isEmpty)
        #expect(throws: Never.self) {
            try document.perform(.setUnits(DocumentUnits(length: .inches)), name: UndoName.changeUnits)
        }
        #expect(document.units.length == .inches)
        #expect(document.undoName == "Change Units")
        document.undo()
        #expect(document.units == .millimetres)
        document.redo()
        #expect(document.units.length == .inches)
    }

    @Test func thePrecisionStepHasItsName() {
        #expect(UndoName.changePrecision == "Change Precision")
    }
}
