import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Removing a node, a disconnect and a connect that replaces a wire take the wires they remove out of every tie in the same
/// command, a tie left with fewer than two wires goes (I2), and undo puts every tie back exactly (cable ties spec §3.2).
@MainActor
struct TieStrippingTests {
    let scene = TieGraph()

    func applying(_ command: GraphCommand, to start: Graph) throws -> (graph: Graph, inverse: GraphCommand) {
        var g = start
        let inverse = try g.apply(command, registry: testRegistry)
        return (g, inverse)
    }

    func undone(_ applied: (graph: Graph, inverse: GraphCommand)) throws -> Graph {
        var g = applied.graph
        try g.apply(applied.inverse, registry: testRegistry)
        return g
    }

    @Test func removingANodeTakesTheWiresIntoItOutOfTheirTies() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a]), tie(2, [scene.s2a, scene.s2b])])
        let removed = try applying(.removeNode(scene.s1.id), to: start)
        #expect(removed.graph.ties[tieID(1)] == nil, "left with one wire, the tie goes")
        #expect(removed.graph.ties[tieID(2)] == start.ties[tieID(2)], "a tie the node never reached is untouched")
        #expect(try undone(removed) == start)
    }

    @Test func aWireOutOfARemovedNodeLeavesItsTiesToo() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a])])
        let removed = try applying(.removeNode(scene.c3.id), to: start)
        #expect(removed.graph.ties[tieID(1)]?.wires == [scene.s1a, scene.s1b])
        #expect(try undone(removed) == start)
    }

    @Test func withNoTieReachedTheInverseIsAsBefore() throws {
        let start = scene.make(ties: [tie(1, [scene.s2a, scene.s2b])])
        let removed = try applying(.removeNode(scene.s1.id), to: start)
        #expect(removed.inverse == .restoreNode(scene.s1, links: [link(scene.c1, "value", scene.s1, "a"),
                                                                link(scene.c2, "value", scene.s1, "b"),
                                                                  ]))
        let cut = try applying(.disconnect(link(scene.c1, "value", scene.s1, "a")), to: start)
        #expect(cut.inverse == .restoreLinks([link(scene.c1, "value", scene.s1, "a")]))
    }

    @Test func disconnectingAWireTakesItOutOfItsTies() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a])])
        let cut = try applying(.disconnect(link(scene.c1, "value", scene.s1, "a")), to: start)
        #expect(cut.graph.ties[tieID(1)]?.wires == [scene.s1b, scene.s2a])
        #expect(try undone(cut) == start)
    }

    /// The new wire lands on the same input the old one left, so it is the same endpoint: it is still never tied implicitly.
    @Test func aReplacingConnectUntiesTheOldWireAndNeverTiesTheNewOne() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b])])
        let replaced = try applying(.connect(link(scene.c3, "value", scene.s1, "a")), to: start)
        #expect(replaced.graph.incomingLink(to: scene.s1a)?.from.node == scene.c3.id)
        #expect(replaced.graph.ties.isEmpty, "the replaced wire left, and one wire is no tie")
        #expect(try undone(replaced) == start)
    }

    @Test func aNewConnectOnAFreeInputLeavesTiesAlone() throws {
        var start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b])])
        start.links.removeAll { $0.to == scene.s2b }
        let connected = try applying(.connect(link(scene.c4, "value", scene.s2, "b")), to: start)
        #expect(connected.graph.ties == start.ties)
        #expect(connected.inverse == .disconnect(link(scene.c4, "value", scene.s2, "b")))
    }

    @Test func undoAndRedoThroughTheDocumentRestoreTiesExactly() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a])])
        let document = DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
        try document.perform(.batch([.removeNode(scene.c1.id), .removeNode(scene.s2.id)]), name: UndoName.delete)
        let after = document.graph
        #expect(after.ties.isEmpty, "c1 took s1a, s2 took s2a, and one wire is no tie")
        document.undo()
        #expect(document.graph == start)
        document.redo()
        #expect(document.graph == after)
        document.undo()
        #expect(document.graph == start)
    }

    @Test func insideADefinitionTheSameHolds() throws {
        let doubler = Doubler()
        var definition = doubler.definition
        definition.graph.ties[tieID(1)] = tie(1, [Endpoint(node: doubler.add.id, socket: "a"),
                                                  Endpoint(node: doubler.add.id, socket: "b"),
        ])
        var content = GraphContent(definitions: table([definition]))
        let before = content
        let unwire = GraphCommand.disconnect(link(doubler.input, "value", doubler.add, "a")).at(.definition(doubler.id))
        let inverse = try content.apply(unwire, registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.ties.isEmpty == true)
        try content.apply(inverse, registry: testRegistry)
        #expect(content == before)
    }
}
