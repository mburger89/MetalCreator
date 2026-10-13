import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The selection a canvas editor opens with, through the app's real window (MetalUI C25, gap CT-b; human checks CT-1 and
/// C25-1): a frame's title opens with all of it selected so typing replaces it, a note opens with the caret at the end so
/// typing appends, and every selection the field makes (a key, ⌘A, Delete, typing) comes back to the model.
@MainActor
struct CanvasTypingSelectionWindowTests {
    let fixture = TypingFixture()

    func titleEditor(dock: DockSide = .bottom) async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.kind == .frameTitle)
        return app
    }

    func noteEditor(dock: DockSide = .bottom) async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.kind == .noteText)
        return app
    }

    @Test(arguments: [DockSide.bottom, .left])
    func aTitleOpensWithAllOfItSelectedAndTypingReplacesIt(dock: DockSide) async throws {
        let app = try await titleEditor(dock: dock)
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<7, "nothing is published at focus (MetalUI divergence 266)")
        app.window.typeText("Front")
        #expect(app.editor.commentEdit?.draft == "Front", "the focus did not undo the model's selection (MetalUI divergence 265)")
        #expect(app.editor.commentEdit?.selectedOffsets == 5..<5, "typing published the caret after the new text")
        app.window.typeText(" plate")
        #expect(app.editor.commentEdit?.draft == "Front plate", "and the next typing appends: the field is not re-selected")
        app.window.typeKey(.return)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Front plate")
        #expect(app.editor.document.undoName == "Edit Frame")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func aNoteOpensWithTheCaretAtItsEndAndTypingAppends(dock: DockSide) async throws {
        let app = try await noteEditor(dock: dock)
        #expect(app.editor.commentEdit?.selectedOffsets == 8..<8)
        app.window.typeText("!")
        #expect(app.editor.commentEdit?.draft == "Line one!")
        #expect(app.editor.commentEdit?.selectedOffsets == 9..<9)
        app.window.typeKey(.return)
        app.window.typeText("Two")
        #expect(app.editor.commentEdit?.draft == "Line one!\nTwo")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one!\nTwo")
        #expect(app.editor.document.undoName == "Edit Note")
    }

    @Test func aNoteEndingInALineBreakOpensOnItsEmptyLastLine() async throws {
        var graph = fixture.graph
        graph.stickies[fixture.note.id]?.text = "one\ntwo\n"
        let app = try await AppWindow.open(graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.selectedOffsets == 8..<8, "after the final line break")
        app.window.typeText("x")
        #expect(app.editor.commentEdit?.draft == "one\ntwo\nx")
    }

    @Test func anEmptyNoteOpensWithTheCaretInIt() async throws {
        var graph = fixture.graph
        graph.stickies[fixture.otherNote.id]?.text = ""
        let app = try await AppWindow.open(graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.otherNote.id))
        #expect(app.editor.commentEdit?.id == fixture.otherNote.id)
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<0)
        app.window.typeText("Hi")
        #expect(app.editor.commentEdit?.draft == "Hi")
    }

    @Test func theKeysPublishWhatTheyDoBackToTheModel() async throws {
        let app = try await titleEditor()
        app.window.typeKey(.leftArrow)
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<0, "an arrow collapses the selection to its start")
        app.window.typeKey(.rightArrow, modifierFlags: .shift)
        app.window.typeKey(.rightArrow, modifierFlags: .shift)
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<2, "shift-arrows extend it")
        app.window.typeText("F")
        #expect(app.editor.commentEdit?.draft == "Facket", "typing replaced the two selected Characters")
        app.window.typeKey("a", modifierFlags: .primary)
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<6, "⌘A selects the lot")
        app.window.typeKey(.delete)
        #expect(app.editor.commentEdit?.draft == "")
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<0)
        app.window.typeText("Z")
        #expect(app.editor.commentEdit?.draft == "Z")
    }

    @Test func aNoteIsSelectedAllByCommandAAndReplacedByTyping() async throws {
        let app = try await noteEditor()
        app.window.typeKey("a", modifierFlags: .primary)
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<8)
        app.window.typeText("New")
        #expect(app.editor.commentEdit?.draft == "New")
        #expect(app.editor.commentEdit?.selectedOffsets == 3..<3)
    }

    @Test func aClickInsideTheEditorMovesTheCaretAndPublishesIt() async throws {
        let app = try await titleEditor()
        let field = try #require(try app.window.focusedElement)
        app.window.click(at: Point(x: field.frame.origin.x + Pixels(1), y: field.frame.origin.y + field.frame.size.height / 2))
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<0, "a click at the field's left edge puts the caret at the start")
        app.window.typeText("Q")
        #expect(app.editor.commentEdit?.draft == "QBracket", "and nothing was replaced")
    }

    @Test func eachEditOpensFreshNotWhereTheLastOneEnded() async throws {
        let app = try await titleEditor()
        app.window.typeText("A")
        app.window.typeKey(.return)
        #expect(app.editor.commentEdit == nil)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.selectedOffsets == 0..<1, "the one-Character title is all selected again")
        app.window.typeText("B")
        #expect(app.editor.commentEdit?.draft == "B")
    }

    @Test func escapeAfterTypingOverASelectedTitleKeepsTheTitle() async throws {
        let app = try await titleEditor()
        app.window.typeText("Gone")
        app.window.typeKey(.escape)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
    }
}
