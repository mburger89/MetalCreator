import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorApp

/// Every drawing edit is one named undo step through the document's own stack (drawings plan R2, R26).
@MainActor
struct DrawingUndoTests {
    @Test func aDrawingEditIsOneNamedStep() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        _ = await app.placeBaseView()
        #expect(app.undoTitle == "Undo Add View")
    }

    @Test func undoRestoresTheEditorsDocument() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        let editor = app.drawing.editor
        _ = await app.placeBaseView()
        #expect(editor.document.sheets[0].views.count == 1)
        app.undo()
        #expect(editor.document.sheets[0].views.isEmpty, "the editor shows the previous drawings")
        app.redo()
        #expect(editor.document.sheets[0].views.count == 1)
        app.undo()
        app.undo()
        #expect(editor.document.sheets.isEmpty && editor.currentSheet == nil, "the sheet went with its step")
        await app.settle()
        #expect(app.document.drawingView?.sheet == nil)
    }

    @Test func aDragIsOneStep() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        let id = try #require(await app.placeBaseView(at: Vector2(150, 120)))
        let editor = app.drawing.editor
        let placed = try #require(editor.document.sheets[0].view(id)?.center)
        let start = editor.transform.screenPoint(placed)
        editor.primaryChanged(to: start, modifiers: [])
        for step in 1...10 {
            editor.primaryChanged(to: start + Vector2(Double(step) * 3, 0), modifiers: [])
        }
        editor.primaryEnded(at: start + Vector2(30, 0), modifiers: [])
        await app.settle()
        #expect(app.undoTitle == "Undo Move View")
        let moved = try #require(editor.document.sheets[0].view(id)?.center)
        #expect(moved.x > placed.x)
        app.undo()
        #expect(app.undoTitle == "Undo Add View", "one undo took back the whole drag")
        #expect(editor.document.sheets[0].view(id)?.center == placed)
    }

    @Test func drawingEditsMakeTheDocumentEditedAndSavingClearsIt() async throws {
        let app = await makeApp(DrawingBox().graph)
        #expect(!app.isEdited)
        app.setMode(.drawing)
        #expect(!app.isEdited)
        app.drawing.editor.addSheet()
        #expect(app.isEdited)
        let url = temporaryURL("sheet.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        #expect(!app.isEdited)
    }

    @Test func anEditIsRefusedWhileAnAlertIsUpAndTheEditorIsPutBack() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        app.alert = .problem(AppProblem("Busy", "An alert is up."))
        let before = app.drawing.editor.document
        app.drawing.editor.addSheet()
        #expect(app.document.drawings == before && app.drawing.editor.document == before)
    }
}
