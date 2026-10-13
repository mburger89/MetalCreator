import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// An input method composing in a canvas editor, through the app's real window (MetalUI C28, gap CT-d; human check
/// C25-3): marked text is in the field and not in the model's draft; committing it is one write and one undo step;
/// cancelling it changes nothing; the selection the editor opened with survives it; and a press elsewhere, which now
/// resigns the focus (C24), drops the composition uncommitted (MetalUI `IM-I`) and ends the edit with the text the
/// field held before it.
@MainActor
struct CanvasTypingCompositionWindowTests {
    let fixture = TypingFixture()

    func titleEditor() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.kind == .frameTitle)
        return app
    }

    func noteEditor() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.kind == .noteText)
        return app
    }

    // MARK: A title

    @Test func markedTextInATitleIsNotInTheDraftAndTheOpeningSelectionStays() async throws {
        let app = try await titleEditor()
        #expect(app.window.setMarkedText("ni"))
        #expect(app.window.markedText == "ni")
        #expect(app.editor.commentEdit?.draft == "Bracket", "the model has not heard of the marked text")
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<7, "and the selection the edit opened with is still the model's")
        #expect(try app.window.focusedElement?.value == "Bracket", "accessibility reports committed text only (MetalUI divergence 325)")
        #expect(!app.editor.document.canUndo)
    }

    @Test func aCandidateCommittedOverTheSelectedTitleIsOneStep() async throws {
        let app = try await titleEditor()
        app.window.setMarkedText("ni")
        app.window.setMarkedText("nihao")
        #expect(app.window.commitMarkedText("你好"))
        #expect(app.window.markedText == "")
        #expect(app.editor.commentEdit?.draft == "你好", "the candidate replaced the selected title")
        #expect(app.editor.commentEdit?.selectedOffsets == 2..<2, "the commit published the caret after it")
        app.window.typeText("!")
        #expect(app.editor.commentEdit?.draft == "你好!", "typing after the composition appends: the title is not selected again")
        app.window.typeKey(.return)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "你好!")
        #expect(app.editor.document.undoName == "Edit Frame")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
        #expect(!app.editor.document.canUndo, "one step for the composition and the typing after it")
    }

    @Test func committingTheMarkedTextAsItStandsWritesItOnce() async throws {
        let app = try await titleEditor()
        app.window.setMarkedText("ni")
        #expect(app.window.commitMarkedText())
        #expect(app.editor.commentEdit?.draft == "ni")
        #expect(app.window.markedText == "")
        app.window.typeKey(.return)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "ni")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
    }

    @Test func aCancelledCompositionLeavesTheTitleAndItsSelection() async throws {
        let app = try await titleEditor()
        app.window.setMarkedText("hao")
        #expect(app.window.cancelMarkedText())
        #expect(app.window.markedText == "")
        #expect(app.editor.commentEdit?.draft == "Bracket")
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<7)
        app.window.typeText("Z")
        #expect(app.editor.commentEdit?.draft == "Z", "the opening selection was kept, so typing still replaces the title")
        app.window.typeKey(.escape)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
    }

    @Test func aCancelledCompositionCommittedAsIsChangesNothing() async throws {
        let app = try await titleEditor()
        app.window.setMarkedText("hao")
        app.window.cancelMarkedText()
        app.window.typeKey(.return)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
        #expect(!app.editor.document.canUndo, "an unchanged title records nothing")
    }

    @Test(arguments: InertSpot.allCases)
    func aPressOnChromeWhileComposingDropsTheCompositionAndEndsTheTitleEditUnchanged(spot: InertSpot) async throws {
        let app = try await titleEditor()
        app.window.setMarkedText("nihao")
        #expect(app.window.markedText == "nihao")
        app.window.click(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil, "the press resigned the focus and the focus-loss commit ended the edit")
        #expect(app.window.markedText == "", "the composition was dropped, not committed (MetalUI IM-I)")
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
        #expect(!app.editor.document.canUndo, "nothing was written")
        #expect(try app.window.focusedElement == nil)
    }

    // MARK: A note

    @Test func aCandidateCommittedAtTheEndOfANoteIsOneStep() async throws {
        let app = try await noteEditor()
        app.window.setMarkedText("ni")
        #expect(app.editor.commentEdit?.draft == "Line one")
        #expect(app.editor.commentEdit?.selectedOffsets == 8..<8, "the caret the edit opened with")
        #expect(try app.window.focusedElement?.value == "Line one")
        app.window.commitMarkedText("你")
        #expect(app.editor.commentEdit?.draft == "Line one你")
        #expect(app.editor.commentEdit?.selectedOffsets == 9..<9)
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one你")
        #expect(app.editor.document.undoName == "Edit Note")
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo)
    }

    @Test func aCandidateCommittedMidLineLandsAtTheCaretAndPublishesTheCaretAfterIt() async throws {
        let app = try await noteEditor()
        app.window.typeKey(.leftArrow, modifierFlags: .option)
        #expect(app.editor.commentEdit?.selectedOffsets == 5..<5, "the caret is before \"one\"")
        app.window.setMarkedText("ni")
        #expect(app.editor.commentEdit?.draft == "Line one")
        #expect(app.editor.commentEdit?.selectedOffsets == 5..<5, "the model's selection is not moved by the composition")
        app.window.commitMarkedText("你")
        #expect(app.editor.commentEdit?.draft == "Line 你one")
        #expect(app.editor.commentEdit?.selectedOffsets == 6..<6)
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line 你one")
        #expect(app.editor.document.undoName == "Edit Note")
    }

    @Test func aCancelledCompositionInANoteLeavesItsTextAndCaret() async throws {
        let app = try await noteEditor()
        app.window.setMarkedText("hao")
        app.window.cancelMarkedText()
        #expect(app.editor.commentEdit?.draft == "Line one")
        #expect(app.editor.commentEdit?.selectedOffsets == 8..<8)
        app.window.typeText("!")
        #expect(app.editor.commentEdit?.draft == "Line one!")
        app.window.typeKey(.escape)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo)
    }

    @Test(arguments: InertSpot.allCases)
    func aPressWhileComposingKeepsWhatWasTypedBeforeTheCompositionAndNothingOfIt(spot: InertSpot) async throws {
        let app = try await noteEditor()
        app.window.typeText(" two")
        app.window.setMarkedText("nihao")
        #expect(app.window.markedText == "nihao")
        app.window.click(at: try spot.point(in: app))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil)
        #expect(app.window.markedText == "")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one two", "the typed text committed; the marked text did not")
        #expect(app.editor.document.undoName == "Edit Note")
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo, "one step")
    }

    @Test func aPressOnTheViewportWhileComposingInANoteEndsTheEditUnchanged() async throws {
        let app = try await noteEditor()
        app.window.setMarkedText("nihao")
        #expect(app.window.markedText == "nihao")
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        try await app.window.runUntilIdle()
        #expect(app.editor.commentEdit == nil && app.window.markedText == "")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && !app.editor.document.canUndo)
    }

    // MARK: Undo in the field (human check C25-7)

    @Test func commandZInTheFieldAfterTheOpeningSelectionRestoresTheTitleAndItsSelection() async throws {
        let app = try await titleEditor()
        app.window.typeText("Z")
        #expect(app.editor.commentEdit?.draft == "Z")
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.commentEdit?.draft == "Bracket", "MetalUI's contract: the typing is undone, the written selection comes back")
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<7)
        #expect(app.editor.commentEdit != nil && !app.editor.document.canUndo, "the edit stays open and the document is untouched")
        app.window.typeKey(.escape)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
    }
}
