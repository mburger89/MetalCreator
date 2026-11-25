#if canImport(CreatorOCCT)
// Test fixture file: the bracket's drawing sheet for the drawing benchmarks.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp

/// An A3 sheet of the §7.2 bracket for `DrawingBench`.
enum DrawingBenchFixtures {
    /// The drawings document with the bracket's Front, Right, Top and Isometric views on the app's current (empty) sheet, at the
    /// scale plan R8 picks for the first of them. Nothing is applied: the app's drawings are as they were. The app must be in
    /// Drawing mode with one empty sheet.
    @MainActor
    static func bracketSheet(_ app: AppModel) async throws -> DrawingDocument {
        let editor = app.drawing.editor
        let empty = editor.document
        // The editor's own first placement sets the sheet's scale (R8); read it, then put the empty sheet back.
        editor.press(.baseView)
        editor.primaryEnded(at: editor.transform.screenPoint(Vector2(120, 190)), modifiers: [])
        await app.settle()
        let placed = try #require(editor.document.sheets.first)
        let source = try #require(placed.views.first?.source)
        let scale = placed.scale
        try app.document.perform(.setDrawings(empty), name: "Test")
        app.refreshDrawing()
        await app.settle()

        var document = empty
        let views: [(StandardOrientation, Vector2)] = [
            (.front, Vector2(120, 190)), (.right, Vector2(300, 190)), (.top, Vector2(120, 90)),
            (.isometricFrontRight, Vector2(300, 90)),
        ]
        document.sheets[0].scale = scale
        for (orientation, center) in views {
            document.sheets[0].setView(DrawingView(
                kind: .base, source: source, orientation: .standard(orientation), center: center))
        }
        return document
    }
}
#endif
