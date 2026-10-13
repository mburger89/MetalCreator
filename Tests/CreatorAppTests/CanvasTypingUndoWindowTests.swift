import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// ⌘Z and ⇧⌘Z around a canvas edit, through the app's real window (human check CT-8). Between edits the Edit menu's ⌘Z
/// undoes the document's last step; while an editor is focused MetalUI's field keeps ⌘Z before the app's command (KF-C),
/// so it undoes the typing in the field and leaves the document alone. The second test pins that measured answer.
@MainActor
struct CanvasTypingUndoWindowTests {
    let fixture = TypingFixture()

    /// The app with the note's text committed as "Line one New", one undo step, the pointer over the canvas.
    func afterOneEdit() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText(" New")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one New")
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        return app
    }

    @Test func commandZRestoresTheOldTextAndShiftCommandZTheNewOneInOneStepEach() async throws {
        let app = try await afterOneEdit()
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(!app.editor.document.canUndo, "the edit was a single step")
        app.window.typeKey("z", modifierFlags: [.primary, .shift])
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one New")
        #expect(!app.editor.document.canRedo)
    }

    @Test func commandZWhileAnEditorIsFocusedUndoesTheTypingAndLeavesTheDocumentAlone() async throws {
        let app = try await afterOneEdit()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText(" Draft")
        #expect(app.editor.commentEdit?.draft.hasSuffix(" Draft") == true)
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.commentEdit?.draft == "Line one New", "the field took ⌘Z: the typing is gone")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one New", "and the document did not move")
        #expect(app.editor.document.undoName == "Edit Note" && !app.editor.document.canRedo)
        #expect(app.editor.commentEdit != nil, "the edit stays open")
    }
}
