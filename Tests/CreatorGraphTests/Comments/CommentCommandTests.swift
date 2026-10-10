import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The four comment commands (canvas comments spec 2026-10-09 §7): each is reversible, a refused one changes
/// nothing, and none of them re-evaluates (comments never affect evaluation).
@MainActor
struct CommentCommandTests {
    func apply(_ command: GraphCommand, to start: Graph = Graph()) throws -> (graph: Graph, inverse: GraphCommand) {
        var g = start
        let inverse = try g.apply(command, registry: testRegistry)
        return (g, inverse)
    }

    @Test func settingAddsAndItsInverseRemoves() throws {
        let added = try apply(.setSticky(note(1)))
        #expect(added.graph.stickies[commentID(1)] == note(1))
        #expect(added.inverse == .removeSticky(commentID(1)))
        let framed = try apply(.setFrame(box(2)))
        #expect(framed.graph.frames[commentID(2)] == box(2))
        #expect(framed.inverse == .removeFrame(commentID(2)))
    }

    @Test func settingAgainReplacesWholeAndItsInverseRestoresTheOld() throws {
        let start = try apply(.setSticky(note(1, "Old"))).graph
        var moved = note(1, "New", at: Vector2(40, 50))
        moved.accent = .green
        let replaced = try apply(.setSticky(moved), to: start)
        #expect(replaced.graph.stickies == [commentID(1): moved])
        #expect(replaced.inverse == .setSticky(note(1, "Old")))
        var back = replaced.graph
        try back.apply(replaced.inverse, registry: testRegistry)
        #expect(back == start)
    }

    @Test func removingReturnsTheCommentAndUndoPutsItBack() throws {
        var g = Graph()
        g.stickies[commentID(1)] = note(1)
        g.frames[commentID(2)] = box(2)
        for command in [GraphCommand.removeSticky(commentID(1)), .removeFrame(commentID(2))] {
            let removed = try apply(command, to: g)
            #expect(removed.graph.commentIDs.count == 1)
            var back = removed.graph
            try back.apply(removed.inverse, registry: testRegistry)
            #expect(back == g)
        }
    }

    @Test func aBadEditIsRefusedAndChangesNothing() {
        var g = Graph()
        g.stickies[commentID(1)] = note(1)
        let start = g
        let refused: [GraphCommand] = [
            .removeSticky(commentID(9)), .removeFrame(commentID(1)), .removeSticky(commentID(2)),
            .setSticky(StickyNote(id: commentID(1), frame: CanvasRect(origin: Vector2(.nan, 0), size: Vector2(1, 1)))),
            .setFrame(CommentFrame(id: commentID(3), frame: CanvasRect(origin: .zero, size: Vector2(.infinity, 1)))),
            .setFrame(CommentFrame(id: commentID(3), frame: CanvasRect(origin: .zero, size: Vector2(-1, 5)))),
            .setFrame(box(1)),
            .batch([.setSticky(note(4)), .removeFrame(commentID(8))]),
        ]
        for command in refused {
            #expect(throws: GraphError.self) { try g.apply(command, registry: testRegistry) }
            #expect(g == start, "\(command)")
        }
        var withFrame = start
        withFrame.frames[commentID(2)] = box(2)
        #expect(throws: GraphError.self) { try withFrame.apply(.setSticky(note(2)), registry: testRegistry) }
    }

    @Test func commentsTouchNoNodeAndAffectNoResult() {
        let commands: [GraphCommand] = [.setSticky(note(1)), .removeSticky(commentID(1)), .setFrame(box(2)), .removeFrame(commentID(2))]
        for command in commands {
            #expect(command.touchedNodes.isEmpty)
            #expect(!command.affectsResults)
        }
        #expect(!GraphCommand.batch(commands).affectsResults)
        #expect(GraphContent().affectsResults(.batch(commands)) == false)
    }

    @Test func aCommentEditIsOneUndoStepAndNeverReevaluates() async throws {
        let constant = makeNode(ConstantNode.self, ["value": .number(3)], output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([constant])), registry: testRegistry, kernel: FakeKernel())
        await document.waitForEvaluation()
        let evaluated = try #require(document.results[constant.id])
        #expect(evaluated.state.isSuccess)
        try document.perform(.batch([.setSticky(note(1)), .setFrame(box(2))]))
        #expect(!document.isEvaluating, "no evaluation was scheduled")
        #expect(document.results[constant.id]?.outputs?["value"]?.numbers == evaluated.outputs?["value"]?.numbers)
        #expect(document.results[constant.id]?.state.isSuccess == true, "still done, not marked stale")
        #expect(document.graph.commentIDs == [commentID(1), commentID(2)])
        document.undo()
        #expect(document.graph.commentIDs.isEmpty && !document.canUndo)
        document.redo()
        #expect(document.graph.commentIDs.count == 2)
    }

    @Test func aDefinitionsInsideHasItsOwnComments() throws {
        let doubler = Doubler()
        let node = instance(of: doubler.definition, ["value": .number(4)], output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([node]), definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        try document.perform(.setSticky(note(1, "Inside")), at: .definition(doubler.id))
        #expect(document.graph.stickies.isEmpty, "the top level has none")
        #expect(document.definitions[doubler.id]?.graph.stickies[commentID(1)]?.text == "Inside")
        document.undo()
        #expect(document.definitions[doubler.id]?.graph.stickies.isEmpty == true)
        #expect(throws: GraphError.self) { try document.perform(.setSticky(note(2)), at: .definition(GroupID())) }
    }

    @Test func aCommentEditMakesTheDocumentDirty() throws {
        let document = DocumentModel(registry: testRegistry, kernel: FakeKernel())
        let saved = document.content
        try document.perform(.setSticky(note(1)))
        #expect(document.content != saved)
        document.undo()
        #expect(document.content == saved)
    }
}
