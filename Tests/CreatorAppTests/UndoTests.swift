import CreatorEditor
import CreatorGraph
import Testing
@testable import CreatorApp

/// Undo and Redo from the menu bar and the top bar settle a typed inspector value first (M6, carry-over
/// "NumberEntry commits only on Return").
@MainActor
struct UndoTests {
    @Test func undoAndRedoCommitATypedValueFirst() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(20)))
        app.editor.selection = [box.extrude.id]
        guard case .slider(let field, _)? = app.editor.inspectorPage.sections.first?.rows.dropFirst().first else {
            Issue.record("no Distance slider"); return
        }
        func distance() -> ConstantValue? { app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] }
        func type(_ text: String) {
            app.editor.notePendingEntry(PendingEntry(text: text, commit: { app.editor.setNumber(field, to: $0) }))
        }
        type("33")
        app.undo()
        #expect(distance() == .number(20), "⌘Z undoes the typed value, not the step before it")
        app.redo()
        #expect(distance() == .number(33))
        app.undo()
        app.undo()
        #expect(distance() == .number(10))
        type("44")
        app.redo()
        #expect(distance() == .number(44), "the typed value is kept")
        #expect(!app.document.canRedo, "it is a new edit, so nothing is left to redo")
        app.editor.commitPendingEntry()
        #expect(distance() == .number(44), "nothing was left to commit later")
    }
}
