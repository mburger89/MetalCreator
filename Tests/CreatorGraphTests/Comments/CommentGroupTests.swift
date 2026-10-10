import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// How comments meet the group commands (canvas comments spec 2026-10-09 §7, groups spec §5): comments belong to a
/// level, so Group leaves the level's comments where they are, Make Unique copies a definition's own with it, and
/// Ungroup splices the definition's own comments into the level, offset like its nodes, in the same undo step.
@MainActor
struct CommentGroupTests {
    let scene = GroupScene()

    func document(comments: [StickyNote] = []) -> DocumentModel {
        var start = graph(scene.nodes, scene.links)
        start.sortLinks()
        for note in comments { start.stickies[note.id] = note }
        return DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func groupingLeavesTheLevelsCommentsWhereTheyAreAndUndoRestoresThem() throws {
        let sticky = note(1, "Stays", at: Vector2(50, 50))
        let document = document(comments: [sticky])
        let before = document.content
        let edit = try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        #expect(document.graph.stickies == [sticky.id: sticky])
        #expect(document.definitions.values.allSatisfy { $0.graph.stickies.isEmpty })
        document.undo()
        #expect(document.content == before)
    }

    @Test func makeUniqueCopiesTheDefinitionsOwnComments() throws {
        var doubler = Doubler()
        doubler.definition.graph.stickies[commentID(5)] = note(5, "Inside")
        doubler.definition.graph.frames[commentID(6)] = box(6, "Inner")
        let kept = instance(of: doubler.definition, output: true), split = instance(of: doubler.definition, output: true)
        var start = graph([kept, split])
        start.sortLinks()
        let document = DocumentModel(file: GraphFile(graph: start, definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let edit = try GroupCommands.makeUnique(split.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        let copy = try #require(document.definitions.values.first { $0.id != doubler.id })
        #expect(copy.graph.stickies[commentID(5)]?.text == "Inside" && copy.graph.frames[commentID(6)]?.title == "Inner")
        try document.perform(.setSticky(note(5, "Changed")), at: .definition(copy.id))
        #expect(document.definitions[doubler.id]?.graph.stickies[commentID(5)]?.text == "Inside", "the original is untouched")
    }

    @Test func ungroupingSplicesTheDefinitionsNoteAndFrameIntoTheLevelAtTheNodesOffsetAndOneUndoRestoresBoth() throws {
        var doubler = Doubler()
        doubler.definition.graph.stickies[commentID(5)] = note(5, "Inside", at: Vector2(10, 20))
        doubler.definition.graph.frames[commentID(6)] = box(6, "Inner", at: Vector2(30, 40))
        var node = instance(of: doubler.definition, ["value": .number(4)], output: true)
        node.position = Vector2(100, 200)
        let sticky = note(1, "Outside")
        var start = graph([node])
        start.stickies[sticky.id] = sticky
        let document = DocumentModel(file: GraphFile(graph: start, definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let before = document.content
        let edit = try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        #expect(document.definitions.isEmpty)
        #expect(document.graph.stickies[sticky.id] == sticky, "the level's own note stays")
        let spliced = document.graph.stickies.values.filter { $0.id != sticky.id }
        #expect(spliced.map(\.text) == ["Inside"] && spliced.first?.frame.origin == Vector2(110, 220))
        #expect(document.graph.frames.values.map(\.title) == ["Inner"]
                && document.graph.frames.values.first?.frame.origin == Vector2(130, 240))
        #expect(document.graph.stickies[commentID(5)] == nil && document.graph.frames[commentID(6)] == nil, "fresh IDs")
        document.undo()
        #expect(document.content == before, "one undo brings back the definition and the node, and removes both comments")
    }
}
