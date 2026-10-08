import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// A number typed into the inspector without Return is committed when the user clicks away, to the field it was
/// typed into (M6, carry-over "NumberEntry commits only on Return").
@MainActor
struct PendingEntryTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let other = testNode(RectangleTestNode.self, id: 2, at: Vector2(0, 300))

    func widthField(_ editor: EditorModel, _ node: NodeID) throws -> InputField {
        editor.selection = [node]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else {
            return try #require(nil as InputField?, "no Width slider")
        }
        return field
    }

    /// What `NumberEntry` records after a keystroke in `field` (its clear action only for an optional input).
    func typed(_ text: String, into field: InputField, _ editor: EditorModel) -> PendingEntry {
        var clear: (@MainActor () -> Void)?
        if field.isOptional { clear = { editor.clearInput(field) } }
        return PendingEntry(text: text, commit: { editor.setNumber(field, to: $0) }, clear: clear)
    }

    @Test func aCanvasPressCommitsTheTypedValueAsOneStep() throws {
        let editor = makeEditor([rect])
        let field = try widthField(editor, rect.id)
        editor.notePendingEntry(typed("75", into: field, editor))
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil, "nothing is written while typing")
        editor.pointerPressed(at: Vector2(900, 900))
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(75))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
        #expect(!editor.document.canUndo)
    }

    @Test func changingTheSelectionCommitsToTheNodeItWasTypedFor() throws {
        let editor = makeEditor([rect, other])
        let field = try widthField(editor, rect.id)
        editor.notePendingEntry(typed("42", into: field, editor))
        editor.selection = [other.id]
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(42))
        #expect(editor.graph.nodes[other.id]?.inputValues["width"] == nil)
    }

    @Test func anEntryIsCommittedOnceAndAnUnreadableOneIsDiscarded() throws {
        let editor = makeEditor([rect])
        let field = try widthField(editor, rect.id)
        editor.notePendingEntry(typed("abc", into: field, editor))
        editor.commitPendingEntry()
        #expect(!editor.document.canUndo, "an unreadable entry writes nothing")
        editor.notePendingEntry(typed("30", into: field, editor))
        editor.commitPendingEntry()
        editor.setNumber(field, to: 31)
        editor.commitPendingEntry()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(31), "the entry did not run twice")
    }

    @Test func anEmptiedOptionalFieldClearsWhenCommitted() throws {
        let grid = testNode(GridPointsTestNode.self, id: 8, at: .zero)
        let editor = makeEditor([grid], registry: inspectorTestRegistry)
        editor.selection = [grid.id]
        guard case .integer(let total)? = editor.inspectorPage.sections.first?.rows.last else {
            Issue.record("no total row"); return
        }
        editor.setNumber(total, to: 6)
        editor.notePendingEntry(typed(" ", into: total, editor))
        editor.commitPendingEntry()
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == nil)
    }

    @Test func aFieldDiscardsItsOwnEntryWhenItsValueChangesUnderneath() throws {
        let editor = makeEditor([rect])
        let field = try widthField(editor, rect.id)
        let owner = UUID()
        var entry = typed("75", into: field, editor)
        entry.owner = owner
        editor.notePendingEntry(entry)
        editor.setNumber(field, to: 20)
        editor.discardPendingEntry(ownedBy: owner)
        editor.commitPendingEntry()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(20), "the stale 75 was not written")
    }

    @Test func aFieldDoesNotDiscardAnotherFieldsEntry() throws {
        let editor = makeEditor([rect])
        let field = try widthField(editor, rect.id)
        var entry = typed("75", into: field, editor)
        entry.owner = UUID()
        editor.notePendingEntry(entry)
        editor.discardPendingEntry(ownedBy: UUID())
        editor.commitPendingEntry()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(75))
    }
}
