import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Where a canvas edit's focus goes and what ends it, with the inspector's note box beside it (human checks CT-9,
/// CT-10 and CT-11; gaps CM-a and CT-a). Every press and key goes through the app's real window.
@MainActor
struct CanvasTypingFocusWindowTests {
    let fixture = TypingFixture()

    func open() async throws -> AppWindow {
        try await AppWindow.open(fixture.graph)
    }

    /// The inspector's multi-line note box (the canvas editor is a "Note" field too, but it is not in the inspector's column).
    func inspectorBox(_ app: AppWindow) throws -> TestElement {
        try #require(app.window.elements { $0.role == .textArea && $0.frame.origin.x.value >= Float(app.inspectorColumnStart) }.first)
    }

    @Test func aDoubleClickOnAnotherCommentCommitsTheFirstAndFocusesTheNext() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("One ")
        app.window.doubleClick(at: app.centre(ofComment: fixture.otherNote.id))
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.contains("One") == true, "the first edit committed")
        #expect(app.editor.commentEdit?.id == fixture.otherNote.id)
        #expect(try app.window.focusedElement?.value == "Second", "and the next field has the focus")
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.id == fixture.box.id)
        #expect(try app.window.focusedElement?.value == "Bracket")
    }

    @Test func theInspectorsBoxBreaksLinesOnReturnAndCommitsOnCommandReturn() async throws {
        let app = try await open()
        app.window.click(at: app.centre(ofComment: fixture.note.id))
        try app.window.click(try inspectorBox(app))
        app.window.typeText(" A")
        app.window.typeKey(.return)
        app.window.typeText("B")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one", "Return breaks the line and commits nothing")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one A\nB")
        #expect(app.editor.document.undoName == "Edit Note")
    }

    @Test func clickingIntoTheInspectorsBoxCommitsTheCanvasEditFirst() async throws {
        let app = try await open()
        app.editor.canvasSelection = CanvasSelection(comments: [fixture.note.id])
        try await app.window.runUntilIdle()
        let box = try inspectorBox(app)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Canvas ")
        #expect(try inspectorBox(app).value == "Line one", "the inspector shows the old text until the edit commits")
        try app.window.click(box)
        try await app.window.runUntilIdle()   // the field's focus-loss `onChange` runs in the frame after the click
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.contains("Canvas") == true, "and nothing is lost")
        app.window.typeText("!")
        app.window.typeKey(.return, modifierFlags: .primary)
        let text = try #require(app.editor.graph.stickies[fixture.note.id]?.text)
        #expect(text.contains("Canvas") && text.contains("!"), "the inspector box took the next keystroke")
    }

    @Test func aPressOnThePanelsGlassLeavesTheEditorOpenAndTheNextCanvasPressCommits() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Kept ")
        let panel = try #require(app.model.panelPlacement).panel
        app.window.click(at: app.windowPoint(panel.origin + Vector2(4, 4)))
        #expect(app.editor.commentEdit != nil, "a press on the panel's glass resigns nothing (gap CT-a)")
        #expect(try app.window.focusedElement?.role == .textArea)
        app.window.typeText("more ")
        #expect(app.editor.commentEdit?.draft.hasSuffix("Kept more ") == true)
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasSuffix("Kept more ") == true)
    }

    /// Human check CT-2's swatch (decision D4 in the plan): the inspector's accent swatch is a model edit that does not end a canvas
    /// edit. The accent changes at once, the edit stays open with its draft, and the next canvas press commits the text, so
    /// nothing is lost; the two changes are two undo steps. Pinned as measured; D4 may change it.
    @Test func anAccentSwatchPressChangesTheAccentAndLeavesTheEditOpenWithNothingLost() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Sw ")
        let swatches = try app.window.elements {
            $0.role == .button && $0.frame.size.width.value == 14 && $0.frame.origin.x.value >= Float(app.inspectorColumnStart)
        }
        try app.window.click(try #require(swatches.dropFirst().first))
        try await app.window.runUntilIdle()
        #expect(app.editor.graph.stickies[fixture.note.id]?.accent != fixture.note.accent, "the accent changed")
        #expect(app.editor.commentEdit?.draft.hasSuffix("Sw ") == true, "and the edit is still open with its draft")
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasSuffix("Sw ") == true)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && app.editor.document.canUndo)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.accent == fixture.note.accent && !app.editor.document.canUndo)
    }

    /// Human check CT-2's viewport press: it goes through `AppModel+Viewport`, which commits the edit and releases focus
    /// (gap M4-a's stopgap), not through the viewport's draw, so it runs headless.
    @Test func aPressOnTheViewportCommitsTheEditAndClearsFocus() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Vp ")
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasSuffix("Vp ") == true)
        #expect(try app.window.focusedElement == nil)
        #expect(app.editor.document.undoName == "Edit Note")
    }
}
