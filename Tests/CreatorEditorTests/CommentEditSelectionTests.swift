import CreatorGeometry
import CreatorGraph
import Foundation
import MetalUI
import Testing
@testable import CreatorEditor

/// The selection a comment edit opens with and keeps (MetalUI C25, gap CT-b; spec 2026-10-09 §8 Errata (C25 adoption)):
/// the model's side. A frame's title opens with all of it selected so typing replaces it; a note opens with its caret at
/// the end so typing appends; whatever the field publishes after that is stored, and a stale or multi-range value reads
/// safely.
@MainActor
struct CommentEditSelectionTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(600, 400))
    let sticky = note(1, "Line one", at: Vector2(100, 100))
    let frame = box(2, "Bracket", at: Vector2(400, 100))

    func editor() -> EditorModel {
        makeEditor([a], stickies: [sticky], frames: [frame])
    }

    @Test func aTitleOpensWithAllOfItSelected() throws {
        let editor = editor()
        editor.beginEditing(frame.id)
        let edit = try #require(editor.commentEdit)
        #expect(edit.selectedOffsets == 0..<7, "Bracket is seven Characters")
        #expect(edit.selection?.isInsertion == false)
    }

    @Test func aNoteOpensWithTheCaretAtTheEnd() throws {
        let editor = editor()
        editor.beginEditing(sticky.id)
        let edit = try #require(editor.commentEdit)
        #expect(edit.selectedOffsets == 8..<8, "Line one is eight Characters")
        #expect(edit.selection?.isInsertion == true)
    }

    @Test func aMultiLineNoteOpensOnItsLastLine() throws {
        let tall = note(3, "one\ntwo\n", at: Vector2(100, 300))
        let editor = makeEditor([a], stickies: [tall])
        editor.beginEditing(tall.id)
        #expect(editor.commentEdit?.selectedOffsets == 8..<8, "after the final line break, on the empty last line")
    }

    /// Review Focus 1: empty and unusual text opens without a trap, and counts Characters, not scalars or bytes.
    @Test func emptyAndMultiScalarTextOpenWithTheRightSelection() throws {
        let empty = note(3, "", at: Vector2(100, 300))
        let family = box(4, "e\u{301}x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", at: Vector2(400, 300))
        let editor = makeEditor([a], stickies: [empty], frames: [family])
        editor.beginEditing(empty.id)
        #expect(editor.commentEdit?.selectedOffsets == 0..<0)
        editor.cancelCommentEdit()
        editor.beginEditing(family.id)
        #expect(editor.commentEdit?.selectedOffsets == 0..<3, "an accented e, an x and one family emoji: three Characters")
    }

    @Test func aPublishedSelectionIsStoredAndTouchesNothingElse() throws {
        let editor = editor()
        editor.beginEditing(frame.id)
        let before = try #require(editor.commentEdit)
        let text = before.draft
        let moved = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: 3))
        editor.commentSelectionChanged(moved)
        let after = try #require(editor.commentEdit)
        #expect(after.selectedOffsets == 3..<3)
        #expect(after.draft == before.draft && after.owner == before.owner && after.original == before.original)
        #expect(editor.pendingEntry?.owner == before.owner && editor.pendingEntry?.text == "Bracket")
        editor.commitCommentEdit()
        #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo, "a caret move writes nothing")
    }

    @Test func aSelectionWithNoEditIsIgnored() {
        let editor = editor()
        editor.commentSelectionChanged(TextSelection(insertionPoint: "x".startIndex))
        #expect(editor.commentEdit == nil)
    }

    /// Review Focus 2: the draft shrinks under a selection written for the longer text (an undo, a paste): reading it
    /// clamps, never traps.
    @Test func aStaleSelectionReadsClamped() throws {
        let editor = editor()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Hi")
        let edit = try #require(editor.commentEdit)
        #expect(edit.selectedOffsets == 0..<2, "the opening selection spanned seven Characters; the text now has two")
        editor.commentDraftChanged("")
        #expect(editor.commentEdit?.selectedOffsets == 0..<0)
    }

    /// Review Focus 3: a multi-selection acts on its first range (MetalUI divergence 265, 266).
    @Test func aMultiSelectionReadsAsItsFirstRange() throws {
        let editor = editor()
        editor.beginEditing(sticky.id)
        let text = "Line one"
        var set = RangeSet<String.Index>()
        set.insert(contentsOf: text.index(text.startIndex, offsetBy: 5)..<text.endIndex)
        set.insert(contentsOf: text.startIndex..<text.index(text.startIndex, offsetBy: 4))
        editor.commentSelectionChanged(TextSelection(ranges: set))
        #expect(editor.commentEdit?.selectedOffsets == 0..<4)
        editor.commentSelectionChanged(TextSelection(ranges: RangeSet<String.Index>()))
        #expect(editor.commentEdit?.selectedOffsets == nil, "an empty set selects nothing")
    }

    @Test func eachEditOpensWithItsOwnSelectionNotTheLastOnes() throws {
        let editor = editor()
        editor.beginEditing(frame.id)
        editor.commentSelectionChanged(TextSelection(insertionPoint: "Bracket".startIndex))
        editor.commitCommentEdit()
        editor.beginEditing(frame.id)
        #expect(editor.commentEdit?.selectedOffsets == 0..<7, "the title opens all selected again")
        editor.cancelCommentEdit()
        editor.beginEditing(sticky.id)
        #expect(editor.commentEdit?.selectedOffsets == 8..<8)
    }

    @Test func theOpeningSelectionIsADocumentedFunctionOfKindAndText() {
        #expect(CommentEdit.Kind.frameTitle.openingSelection(in: "abc") == TextSelection(range: "abc".startIndex..<"abc".endIndex))
        #expect(CommentEdit.Kind.noteText.openingSelection(in: "abc") == TextSelection(insertionPoint: "abc".endIndex))
    }
}
