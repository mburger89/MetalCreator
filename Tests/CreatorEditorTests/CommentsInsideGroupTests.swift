import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// Comments belong to the level they are on (comments spec Errata (B), groups spec §6): inside a group, adding,
/// editing, pasting, moving and deleting a comment changes the definition's inside, never the top level.
@MainActor
struct CommentsInsideGroupTests {
    @Test func aNoteAddedInsideAGroupIsTheDefinitions() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(editor.addNote(atScreen: Vector2(40, 40)))
        let id = try #require(editor.canvasSelection.comments.first)
        #expect(grouped.current?.graph.stickies[id] != nil)
        #expect(editor.rootGraph.stickies.isEmpty)
        editor.setNoteText(id, to: "Rib")
        #expect(grouped.current?.graph.stickies[id]?.text == "Rib")
    }

    @Test func pastingAndDeletingANoteInsideAGroupChangeOnlyTheDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(editor.addNote(atScreen: Vector2(40, 40)))
        editor.copySelection()
        editor.paste()
        #expect(grouped.current?.graph.stickies.count == 2)
        editor.deleteSelection()
        #expect(grouped.current?.graph.stickies.count == 1)
        #expect(editor.rootGraph.stickies.isEmpty)
        editor.perform(.undo)
        #expect(grouped.current?.graph.stickies.count == 2, "the delete was one step")
    }
}
