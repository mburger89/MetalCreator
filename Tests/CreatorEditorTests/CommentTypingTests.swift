import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorEditor

/// Typing into a comment in place on the canvas (comments typing plan, spec 2026-10-09 §8): the model's side. The edit
/// is a draft until it is committed, as one undo step through `setNoteText` / `setFrameTitle`; Esc throws it away.
@MainActor
struct CommentTypingTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(600, 400))
    let sticky = note(1, "Line one", at: Vector2(100, 100))
    let frame = box(2, "Bracket", at: Vector2(400, 100))
    /// Not symmetric about the diagonal, so the left dock's transpose shows.
    let tall = note(3, "Tall", at: Vector2(100, 300))

    func editor(dock: DockSide = .bottom) -> EditorModel {
        makeEditor([a], stickies: [sticky, tall], frames: [frame], dock: dock)
    }

    @Test func beginningSelectsTheCommentAloneAndChangesNothing() throws {
        let editor = editor()
        editor.selection = [a.id]
        #expect(editor.beginEditing(sticky.id))
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == sticky.id && edit.kind == .noteText)
        #expect(edit.original == "Line one" && edit.draft == "Line one")
        #expect(!editor.document.canUndo)
    }

    @Test func typingThenCommittingIsOneUndoStep() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Line one\nLine two")
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one", "typing alone changes nothing in the graph")
        editor.commitCommentEdit()
        #expect(editor.commentEdit == nil)
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one\nLine two")
        #expect(editor.document.undoName == "Edit Note", "the inspector's path, so the step carries named-undo's name")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]), "the note stays selected")
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one" && !editor.document.canUndo)
    }

    @Test func cancellingPutsTheOldTextBackAndLeavesNothingPending() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Thrown away")
        editor.cancelCommentEdit()
        #expect(editor.commentEdit == nil)
        editor.commitPendingEntry()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one" && !editor.document.canUndo)
    }

    @Test func aFramesTitleIsTrimmedAndCommittedAsOneStep() {
        let editor = editor()
        editor.beginEditing(frame.id)
        #expect(editor.commentEdit?.kind == .frameTitle)
        editor.commentDraftChanged("  Front plate \n")
        editor.commitCommentEdit()
        #expect(editor.graph.frames[frame.id]?.title == "Front plate")
        #expect(editor.document.undoName == "Edit Frame")
        editor.document.undo()
        #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo)
    }

    /// Review Focus 1: an empty or blank title is refused as the inspector refuses it; the bar shows the old title.
    @Test func anEmptyTitleIsRefusedAndTheOldOneStays() {
        let editor = editor()
        for empty in ["", "   ", "\n"] {
            editor.beginEditing(frame.id)
            editor.commentDraftChanged(empty)
            editor.commitCommentEdit()
            #expect(editor.refusal?.message == "A frame needs a title.")
            #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo)
            #expect(editor.commentEdit == nil, "the edit ends and the title bar shows the old title again")
            editor.clearRefusal()
        }
    }

    @Test func anUnchangedTextRecordsNothing() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commitCommentEdit()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Bracket")
        editor.commitCommentEdit()
        #expect(!editor.document.canUndo && editor.refusal == nil)
    }

    @Test func aLateKeystrokeAfterTheEditEndedDoesNothing() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.cancelCommentEdit()
        editor.commentDraftChanged("Too late")
        editor.commitCommentEdit()
        #expect(editor.commentEdit == nil && editor.graph.stickies[sticky.id]?.text == "Line one")
    }

    // MARK: - Every moment the model already commits a typed value

    @Test func aPressElsewhereOnTheCanvasCommits() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        editor.click(Vector2(1200, 800))
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed" && editor.commentEdit == nil)
    }

    @Test func changingTheSelectionCommits() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        editor.selection = [a.id]
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed" && editor.commentEdit == nil)
    }

    /// The shell commits before it saves, exports, undoes or closes (`AppModel`): a canvas edit lands then too.
    @Test func theShellsCommitBeforeSavingCommitsACanvasEdit() {
        let editor = editor()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Saved title")
        editor.commitPendingEntry()
        #expect(editor.graph.frames[frame.id]?.title == "Saved title" && editor.commentEdit == nil)
    }

    // MARK: - One pending entry at a time

    @Test func aFieldTypedIntoWhileTheCanvasIsBeingTypedIntoCommitsTheCanvasEditFirst() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Canvas text")
        var landed: [String] = []
        editor.notePendingEntry(PendingEntry(owner: UUID(), text: "from the inspector", textCommit: { landed.append($0) }))
        #expect(editor.graph.stickies[sticky.id]?.text == "Canvas text" && editor.commentEdit == nil)
        editor.commitPendingEntry()
        #expect(landed == ["from the inspector"], "the inspector's entry now holds the slot, and lands on its own")
    }

    @Test func beginningCommitsATypedInspectorEntryFirstAndTakesTheSlot() {
        let editor = editor()
        var landed: [String] = []
        editor.notePendingEntry(PendingEntry(owner: UUID(), text: "typed in the inspector", textCommit: { landed.append($0) }))
        editor.beginEditing(sticky.id)
        #expect(landed == ["typed in the inspector"])
        #expect(editor.pendingEntry?.owner != nil && editor.pendingEntry?.owner == editor.commentEdit?.owner)
    }

    @Test func beginningAnotherCommentCommitsTheFirst() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("First")
        editor.beginEditing(frame.id)
        #expect(editor.graph.stickies[sticky.id]?.text == "First")
        #expect(editor.commentEdit?.id == frame.id)
        #expect(editor.canvasSelection == CanvasSelection(comments: [frame.id]))
    }

    // MARK: - The field's place

    @Test func theFieldSitsOverTheNoteAndOverTheFramesTitleBar() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 100), size: Vector2(160, 100)))
        editor.beginEditing(frame.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(400, 100), size: Vector2(400, 22)))
    }

    /// Review Focus 2: docked left the graph is drawn transposed, and the field is drawn where the comment is.
    @Test func theLeftDockTransposesTheField() {
        let editor = editor(dock: .left)
        editor.beginEditing(tall.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(300, 100), size: Vector2(100, 160)))
        editor.beginEditing(frame.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 400), size: Vector2(300, 22)))
    }

    /// Review Focus 3: the comment is deleted (undo of its creation, say) while it is being edited.
    @Test func aCommentThatIsGoneHasNoFieldAndNothingToCommit() throws {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        try editor.edit(.removeSticky(sticky.id), name: UndoName.delete)
        #expect(editor.commentEditor == nil)
        editor.commitCommentEdit()
        #expect(editor.graph.stickies[sticky.id] == nil && editor.commentEdit == nil)
    }

    /// Review Focus 3: the panel is hidden mid-edit (its canvas, and so the field, goes away): the edit is committed
    /// then, not left pending to land on a later save.
    @Test func hidingThePanelCommitsTheEdit() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        editor.setDock(.hidden)
        #expect(editor.commentEditor == nil && editor.commentEdit == nil)
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed")
    }

    /// The header's Left / Bottom buttons mid-edit: the edit goes on, and the field follows the comment into the other
    /// drawing (`commentEditor` is computed from the flow each time), the draft kept.
    @Test func changingTheDockMidEditMovesTheFieldAndKeepsTheDraft() {
        let editor = editor()
        editor.beginEditing(tall.id)
        editor.commentDraftChanged("Typed")
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 300), size: Vector2(160, 100)))
        editor.setDock(.left)
        #expect(editor.commentEdit?.draft == "Typed" && editor.commentEdit?.id == tall.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(300, 100), size: Vector2(100, 160)))
        editor.setDock(.bottom)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 300), size: Vector2(160, 100)))
        editor.commitCommentEdit()
        #expect(editor.graph.stickies[tall.id]?.text == "Typed")
    }

    /// User decision 9: a sketch being open locks the level (`isLevelLocked`), not the comments; add-note works then too.
    @Test func typingWorksWhileTheLevelIsLocked() {
        let editor = editor()
        editor.isLevelLocked = true
        #expect(editor.beginEditing(sticky.id))
        editor.commentDraftChanged("Typed during a sketch")
        editor.commitCommentEdit()
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed during a sketch")
    }

    /// Review Focus 4: leaving the group being edited in commits to the level it was typed on.
    @Test func leavingAGroupCommitsTheEditToThatLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(editor.addNote(atScreen: Vector2(40, 40)))
        let id = try #require(editor.canvasSelection.comments.first)
        editor.beginEditing(id)
        editor.commentDraftChanged("Rib")
        editor.exitGroup()
        #expect(grouped.current?.graph.stickies[id]?.text == "Rib")
        #expect(editor.rootGraph.stickies.isEmpty && editor.commentEdit == nil)
    }

    /// Review Focus 1: a title is one line; a line break pasted into it becomes a space.
    @Test func aLineBreakPastedIntoATitleBecomesASpace() {
        let editor = editor()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Front\nplate")
        editor.commitCommentEdit()
        #expect(editor.graph.frames[frame.id]?.title == "Front plate")
    }

    @Test func beginningNeedsACommentThePanelAndNoDragUnderWay() {
        let editor = editor()
        #expect(!editor.beginEditing(commentID(99)) && editor.commentEdit == nil)
        let start = Vector2(1200, 800)
        editor.pointerDragged(from: start, to: start + Vector2(50, 50))
        #expect(editor.interaction != nil)
        #expect(!editor.beginEditing(sticky.id))
        editor.pointerReleased(from: start, at: start + Vector2(50, 50))
        let hidden = makeEditor([], stickies: [sticky], dock: .hidden)
        #expect(!hidden.beginEditing(sticky.id))
    }
}
