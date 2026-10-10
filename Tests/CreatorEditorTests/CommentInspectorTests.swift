import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// Editing the selected comment in the inspector (canvas comments spec 2026-10-09 §7): a note's multi-line text
/// commits on focus loss; a frame's title on Return and refuses empty; the accent; several selected show
/// "N comments selected".
@MainActor
struct CommentInspectorTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let sticky = note(1, "Line one")
    let frame = box(2, "Bracket", at: Vector2(0, 400))

    func editor() -> EditorModel { makeEditor([a], stickies: [sticky], frames: [frame]) }

    @Test func thePageNamesTheOneSelectedCommentOrCountsSeveral() {
        let editor = editor()
        #expect(editor.inspectorPage.comment == nil)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.inspectorPage.comment == .note(id: sticky.id, text: "Line one", accent: .muted))
        editor.canvasSelection = CanvasSelection(comments: [frame.id])
        #expect(editor.inspectorPage.comment == .frame(id: frame.id, title: "Bracket", accent: .muted))
        editor.canvasSelection = CanvasSelection(comments: [sticky.id, frame.id])
        #expect(editor.inspectorPage.comment == .several(count: 2))
        #expect(editor.inspectorPage.comment?.summary == "2 comments selected")
        #expect(CommentPage.note(id: sticky.id, text: "", accent: .pink).summary == nil)
        #expect(editor.inspectorPage.header == nil)
    }

    @Test func aSelectedNodeKeepsTheNodePageAndGoneCommentsAreIgnored() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [a.id], comments: [sticky.id])
        #expect(editor.inspectorPage.comment == nil)
        #expect(editor.inspectorPage.header?.node == a.id, "one node still gets its page")
        editor.canvasSelection = CanvasSelection(comments: [sticky.id, commentID(9)])
        #expect(editor.inspectorPage.comment == .note(id: sticky.id, text: "Line one", accent: .muted), "the gone one isn't counted")
        editor.canvasSelection = CanvasSelection(comments: [commentID(9)])
        #expect(editor.inspectorPage.comment == nil)
    }

    @Test func aNotesTextIsOneUndoStepAndKeepsItsLineBreaks() {
        let editor = editor()
        editor.setNoteText(sticky.id, to: "Line one\nLine two\n\nLine four")
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one\nLine two\n\nLine four")
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one" && !editor.document.canUndo)
        editor.setNoteText(sticky.id, to: "Line one")
        editor.setNoteText(commentID(9), to: "Nobody")
        #expect(!editor.document.canUndo, "an unchanged text and a gone note do nothing")
    }

    @Test func aFramesTitleIsTrimmedAndAnEmptyOneRefused() {
        let editor = editor()
        #expect(editor.setFrameTitle(frame.id, to: "  Front plate \n"))
        #expect(editor.graph.frames[frame.id]?.title == "Front plate")
        editor.document.undo()
        #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo)
        for empty in ["", "   ", "\n"] {
            #expect(!editor.setFrameTitle(frame.id, to: empty))
            #expect(editor.refusal?.message == "A frame needs a title.")
            #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo)
            editor.clearRefusal()
        }
        #expect(editor.setFrameTitle(frame.id, to: "Bracket") && !editor.document.canUndo, "unchanged: nothing recorded")
        #expect(!editor.setFrameTitle(sticky.id, to: "A note is not a frame"))
    }

    @Test func theAccentOfEitherKindIsOneUndoStep() {
        let editor = editor()
        editor.setCommentAccent(sticky.id, to: .pink)
        editor.setCommentAccent(frame.id, to: .cyan)
        #expect(editor.graph.stickies[sticky.id]?.accent == .pink && editor.graph.frames[frame.id]?.accent == .cyan)
        editor.document.undo()
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.accent == .muted && !editor.document.canUndo)
        editor.setCommentAccent(sticky.id, to: .muted)
        #expect(!editor.document.canUndo)
    }

    @Test func typedTextIsCommittedToItsOwnNoteWhenTheSelectionChanges() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        editor.notePendingEntry(PendingEntry(text: "Typed, not yet committed", textCommit: { [editor, id = sticky.id] in
            editor.setNoteText(id, to: $0)
        }))
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one", "nothing is written while typing")
        editor.canvasSelection = CanvasSelection(nodes: [a.id])
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed, not yet committed")
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one" && !editor.document.canUndo)
    }

    @Test func aCanvasPressCommitsTypedTextToo() {
        let editor = editor()
        editor.notePendingEntry(PendingEntry(text: "From the press", textCommit: { [editor, id = sticky.id] in
            editor.setNoteText(id, to: $0)
        }))
        editor.pointerPressed(at: Vector2(900, 900))
        #expect(editor.graph.stickies[sticky.id]?.text == "From the press")
    }

    @Test func commentEditsNeverReevaluate() async {
        let editor = editor()
        await editor.document.waitForEvaluation()
        editor.setNoteText(sticky.id, to: "Changed")
        editor.setCommentAccent(frame.id, to: .green)
        #expect(!editor.document.isEvaluating)
    }

    @Test func eachAccentIsADistinctRoleOfEveryBuiltInTheme() {
        for theme in ColorTheme.builtIns {
            let palette = Palette(theme)
            let colours = AccentRole.allCases.map { palette.accent($0) }
            #expect(Set(colours).count == AccentRole.allCases.count, "\(theme.name): seven different colours")
        }
        #expect(Palette.dracula.accent(.pink) == Palette.dracula.header(for: .selection))
        #expect(Palette.dracula.accent(.muted) == Palette.dracula.header(for: .value))
        #expect(Palette(.nord).accent(.cyan) != Palette(.dracula).accent(.cyan), "it follows the theme")
    }

    @Test(arguments: [0, 1, 2, 3])
    func theInspectorDrawsEveryCommentPage(_ page: Int) {
        let editor = editor()
        editor.canvasSelection = [
            CanvasSelection(),
            CanvasSelection(comments: [sticky.id]),
            CanvasSelection(comments: [frame.id]),
            CanvasSelection(comments: [sticky.id, frame.id]),
        ][page]
        let plain = renderHeadless { InspectorPanel(model: makeEditor([])) }.glyphs.count
        let scene = renderHeadless { InspectorPanel(model: editor) }
        #expect(!scene.glyphs.isEmpty)
        if page > 0 { #expect(scene.glyphs.count > plain, "the comment's section adds text") }
    }
}
