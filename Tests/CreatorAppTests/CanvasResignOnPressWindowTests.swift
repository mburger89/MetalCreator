import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// A press that lands on nothing ends a canvas edit (spec 2026-10-09 §8: "on a press elsewhere"; gap CT-a, adopted from
/// MetalUI C24): `.resignsFocusOnPress()` on the window's root clears the field's focus, and the field's focus-loss
/// commit writes the draft as one step. Every press goes through the app's real window; the focus-loss commit runs in
/// the frame after the press, so each test runs `runUntilIdle()`.
@MainActor
struct CanvasResignOnPressWindowTests {
    let fixture = TypingFixture()

    func open() async throws -> AppWindow {
        try await AppWindow.open(fixture.graph)
    }

    /// The inspector's multi-line note box.
    func inspectorBox(_ app: AppWindow) throws -> TestElement {
        try #require(app.window.elements { $0.role == .textArea && $0.frame.origin.x.value >= Float(app.inspectorColumnStart) }.first)
    }

    @Test(arguments: InertSpot.allCases)
    func aPressOnInertChromeEndsANoteEditInOneStep(spot: InertSpot) async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Kept ")
        app.window.click(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasSuffix("Kept ") == true)
        #expect(try app.window.focusedElement == nil)
        #expect(app.editor.document.undoName == "Edit Note")
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one", "one step wrote the whole draft")
        #expect(!app.editor.document.canUndo)
    }

    @Test(arguments: InertSpot.allCases)
    func aPressOnInertChromeEndsAFrameTitleEditInOneStep(spot: InertSpot) async throws {
        let app = try await open()
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeText("Two")  // the title opens selected, so typing replaces it
        app.window.click(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Two")
        #expect(app.editor.document.undoName == "Edit Frame")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
        #expect(!app.editor.document.canUndo)
    }

    /// Human check CT-2's viewport press: the viewport is under the region too (the shell no longer clears the focus itself).
    @Test func aPressOnTheViewportEndsTheEditInOneStep() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Vp ")
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasSuffix("Vp ") == true)
        #expect(try app.window.focusedElement == nil)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo)
    }

    /// A to B: the press lands on another field, the focus moves straight there, and the first edit commits once.
    @Test func aPressIntoTheInspectorsBoxMovesFocusAndCommitsTheCanvasEditOnce() async throws {
        let app = try await open()
        app.editor.canvasSelection = CanvasSelection(comments: [fixture.note.id])
        try await app.window.runUntilIdle()
        let box = try inspectorBox(app)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Canvas ")
        try app.window.click(box)
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil)
        let focused = try #require(try app.window.focusedElement)
        #expect(focused.role == .textArea && focused.frame.origin.x.value >= Float(app.inspectorColumnStart),
                "the inspector's box has the focus")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasSuffix("Canvas ") == true)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo,
                "the canvas edit is one step, committed once")
    }

    /// A to B between two canvas fields: the first commits once, the second opens focused.
    @Test func aDoubleClickOnAnotherCommentCommitsTheFirstOnce() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("One ")
        app.window.doubleClick(at: app.centre(ofComment: fixture.otherNote.id))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit?.id == fixture.otherNote.id)
        #expect(try app.window.focusedElement?.value == "Second")
        #expect(app.editor.document.undoName == "Edit Note")
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo)
    }

    /// Only a primary press resigns: a secondary press on inert chrome leaves the edit open and focused.
    @Test(arguments: InertSpot.allCases)
    func aSecondaryPressOnInertChromeResignsNothing(spot: InertSpot) async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Kept ")
        app.window.rightClick(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit != nil)
        #expect(try app.window.focusedElement?.role == .textArea)
        app.window.typeText("more ")
        #expect(app.editor.commentEdit?.draft.hasSuffix("Kept more ") == true, "typing still reaches the field")
        #expect(!app.editor.document.canUndo, "nothing was committed")
    }
}
