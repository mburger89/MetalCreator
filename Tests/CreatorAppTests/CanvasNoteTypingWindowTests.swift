import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Typing into a note on the canvas through the app's real window (human checks CT-1, CT-2, CT-5): the double click,
/// the focus, the text input and the keys travel MetalUI's own routing, so a regression in MetalUI's key regions or in
/// the editor's `onKeyPress` handlers fails here, not only in front of a person.
@MainActor
struct CanvasNoteTypingWindowTests {
    let fixture = TypingFixture()

    func open(dock: DockSide = .bottom) async throws -> AppWindow {
        try await AppWindow.open(fixture.graph, dock: dock)
    }

    @Test(arguments: [DockSide.bottom, .left])
    func aDoubleClickOpensAFocusedEditorExactlyOverTheNote(dock: DockSide) async throws {
        let app = try await open(dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.id == fixture.note.id)
        let field = try #require(try app.window.focusedElement, "focus is in the field the moment it appears")
        #expect(field.role == .textArea)
        #expect(field.value == "Line one")
        let rect = try #require(app.editor.frame(ofComment: fixture.note.id))
        #expect(field.frame.origin == app.point(inCanvas: rect.origin))
        #expect(Double(field.frame.size.width.value) == rect.size.x && Double(field.frame.size.height.value) == rect.size.y)
    }

    /// Human check CT-6's geometry: under the canvas's zoom the editor is scaled as the note is and still lies over it.
    @Test(arguments: [0.5, 2.0])
    func theEditorFollowsTheCanvasZoom(zoom: Double) async throws {
        let app = try await AppWindow.open(fixture.graph, zoom: zoom)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        let field = try #require(try app.window.focusedElement)
        let rect = try #require(app.editor.frame(ofComment: fixture.note.id))
        #expect(abs(Double(field.frame.size.width.value) - rect.size.x * zoom) <= 1)
        #expect(abs(Double(field.frame.size.height.value) - rect.size.y * zoom) <= 1)
        let corner = app.point(inCanvas: rect.origin)
        #expect(abs(field.frame.origin.x.value - corner.x.value) <= 1 && abs(field.frame.origin.y.value - corner.y.value) <= 1)
    }

    @Test(arguments: [DockSide.bottom, .left])
    func returnBreaksTheLineAndCommandReturnCommitsOneUndoStep(dock: DockSide) async throws {
        let app = try await open(dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("A")
        app.window.typeKey(.return)
        app.window.typeText("B")
        #expect(app.editor.commentEdit != nil, "Return commits nothing")
        #expect(app.editor.commentEdit?.draft.contains("\n") == true)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one", "typing alone changes nothing in the graph")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.commentEdit == nil)
        let text = try #require(app.editor.graph.stickies[fixture.note.id]?.text)
        #expect(text.contains("A\nB"), "Return broke the line, after the typed A: the caret opens at the end of the note (gap CT-b)")
        #expect(app.editor.document.undoName == "Edit Note")
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func escapeCancelsAndLeavesNothingToUndo(dock: DockSide) async throws {
        let app = try await open(dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Thrown away")
        app.window.typeKey(.escape)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(!app.editor.document.canUndo)
        #expect(try app.window.focusedElement == nil)
    }

    @Test func aClickOnTheCanvasAwayFromTheNoteCommitsAndClearsFocus() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Typed ")
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        let text = try #require(app.editor.graph.stickies[fixture.note.id]?.text)
        #expect(text.contains("Typed") && text.contains("Line one"), "the typed text joined the old, after it (the caret opens at the end)")
        #expect(try app.window.focusedElement == nil)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
    }
}
