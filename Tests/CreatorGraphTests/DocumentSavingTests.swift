import CreatorDrawing
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Saving the drawings the editor holds (drawings plan R15, Task 14): the file carries the editor's newest last-good values, and the
/// open document takes them as a change that is no undo step and no edit.
@MainActor
struct DocumentSavingTests {
    private func document(_ names: String...) -> DocumentModel {
        let sheets = names.map { DrawingSheet(name: $0) }
        return DocumentModel(file: GraphFile(graph: Graph(drawings: DrawingDocument(sheets: sheets))), registry: testRegistry,
                             kernel: FakeKernel())
    }

    private func written(_ data: Data) throws -> GraphFile {
        try GraphFileIO.decode(data, registry: testRegistry)
    }

    @Test func fileDataWithDrawingsWritesThem() throws {
        let model = document("Plate")
        let replaced = DrawingDocument(sheets: [DrawingSheet(name: "Renamed"), DrawingSheet(name: "Second")])
        let data = try model.fileData(savingTo: nil, drawings: replaced)
        #expect(try written(data).graph.drawings.sheets.map(\.name) == ["Renamed", "Second"])
        #expect(model.drawings.sheets.map(\.name) == ["Plate"], "the open document is not changed")
        #expect(try written(model.fileData(savingTo: nil, drawings: nil)).graph.drawings.sheets.map(\.name) == ["Plate"])
        #expect(try written(model.fileData()).graph.drawings.sheets.map(\.name) == ["Plate"], "the old signature forwards nil")
    }

    @Test func didSaveWithDrawingsIsNotAnUndoStep() throws {
        let model = document("Plate")
        let before = model.undoStack.undoEntries.count
        let replaced = DrawingDocument(sheets: [DrawingSheet(name: "Plate"), DrawingSheet(name: "Added")])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("saved-\(UUID().uuidString).mcgraph")
        model.didSave(to: url, drawings: replaced)
        #expect(model.drawings == replaced)
        #expect(model.undoStack.undoEntries.count == before)
        #expect(!model.canUndo)
        #expect(model.documentURL == url)
        model.didSave(to: url, drawings: nil)
        #expect(model.drawings == replaced, "nil leaves the drawings as they are")
    }
}
