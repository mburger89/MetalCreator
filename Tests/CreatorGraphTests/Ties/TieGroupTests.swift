import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Ties follow Group, Ungroup and Make Unique (cable ties spec 2026-10-26 §4.5): a tie goes inside a new group only when every
/// wire it holds does, a wire that crosses the boundary leaves its tie, Ungroup brings a definition's ties back out on the
/// spliced copies, and Make Unique gives the copy ties of its own.
@MainActor
struct TieGroupTests {
    let scene = TieGraph()

    func group(_ ids: Set<NodeID>, in document: DocumentModel) throws -> GroupEdit {
        let edit = try GroupCommands.group(ids, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command, name: UndoName.group)
        return edit
    }

    @Test func groupingEveryWireOfATieMovesItInside() throws {
        let held = tie(1, [scene.s1a, scene.s1b], at: Vector2(250, 150))
        let document = scene.document(ties: [held])
        let before = document.content
        _ = try group([scene.c1.id, scene.c2.id, scene.s1.id], in: document)
        let definition = try #require(document.definitions.values.first)
        #expect(definition.graph.ties == [held.id: CableTie(id: held.id, position: Vector2(150, 50), wires: held.wires)],
                "moved like the nodes, relative to their top-left (100, 100)")
        #expect(document.graph.ties.isEmpty)
        document.undo()
        #expect(document.content == before, "one undo step")
    }

    @Test func aTieWithWiresOutsideKeepsThoseAndStaysOutside() throws {
        let held = tie(1, [scene.s1a, scene.s2a, scene.s2b])
        let document = scene.document(ties: [held])
        _ = try group([scene.c1.id, scene.c2.id, scene.s1.id], in: document)
        #expect(document.graph.ties[held.id]?.wires == [scene.s2a, scene.s2b])
        #expect(document.definitions.values.first?.graph.ties.isEmpty == true)
    }

    /// Grouping c1 and s1: `s1a` moves inside, `s1b` crosses in from c2 outside. Both leave, and one wire is no tie.
    @Test func aWireCrossingTheBoundaryLeavesItsTie() throws {
        let document = scene.document(ties: [tie(1, [scene.s1a, scene.s1b])])
        _ = try group([scene.c1.id, scene.s1.id], in: document)
        #expect(document.graph.ties.isEmpty)
        #expect(document.definitions.values.first?.graph.ties.isEmpty == true)
    }

    @Test func ungroupingBringsTheTiesBackOutOnTheCopies() throws {
        let held = tie(1, [scene.s1a, scene.s1b], at: Vector2(250, 150))
        let document = scene.document(ties: [held])
        let grouped = try group([scene.c1.id, scene.c2.id, scene.s1.id], in: document)
        let node = try #require(grouped.selection.first)
        let edit = try GroupCommands.ungroup(node, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command, name: UndoName.ungroup)
        let add = try #require(edit.selection.compactMap { document.graph.nodes[$0] }.first { $0.typeID == AddNode.typeID })
        #expect(document.graph.ties.count == 1)
        let back = try #require(document.graph.ties.values.first)
        #expect(back.wires == [Endpoint(node: add.id, socket: "a"), Endpoint(node: add.id, socket: "b")])
        #expect(back.position == Vector2(250, 150), "moved by the group node, which stood at the nodes' top-left")
        #expect(back.id != held.id, "a fresh ID, like the spliced nodes'")
        document.undo()
        #expect(document.definitions.values.first?.graph.ties.count == 1, "undo puts it back inside")
    }

    /// Doubler's Group Input feeds both of Add's inputs. Ungrouping an instance whose input is a typed value writes the
    /// value onto them, so no wire is left to tie; one fed by a wire keeps both inner wires, so the tie comes out.
    @Test func aWireThatBecomesAValueOnUngroupLeavesItsTie() throws {
        var doubler = Doubler()
        let innerWires = [Endpoint(node: doubler.add.id, socket: "a"), Endpoint(node: doubler.add.id, socket: "b")]
        doubler.definition.graph.ties[tieID(1)] = tie(1, innerWires)
        let unwired = instance(of: doubler.definition, ["value": .number(4)])
        let wired = instance(of: doubler.definition)
        let constant = tieNode(ConstantNode.self, at: Vector2(-300, 0))
        var start = graph([unwired, wired, constant], [link(constant, "value", wired, "value")])
        start.sortLinks()
        let document = DocumentModel(file: GraphFile(graph: start, definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let fromValue = try GroupCommands.ungroup(unwired.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(fromValue.command, name: UndoName.ungroup)
        #expect(document.graph.ties.isEmpty, "Group Input fed nothing: the inner wires became values")
        let fromWire = try GroupCommands.ungroup(wired.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(fromWire.command, name: UndoName.ungroup)
        let add = try #require(fromWire.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(document.graph.ties.values.map(\.wires)
                == [[Endpoint(node: add.id, socket: "a"), Endpoint(node: add.id, socket: "b")]])
    }

    @Test func makeUniqueGivesTheCopyItsOwnTies() throws {
        var doubler = Doubler()
        let inner = tie(1, [Endpoint(node: doubler.add.id, socket: "a"), Endpoint(node: doubler.add.id, socket: "b")])
        doubler.definition.graph.ties[inner.id] = inner
        let node = instance(of: doubler.definition)
        var content = GraphContent(graph: graph([node]), definitions: table([doubler.definition]))
        let edit = try GroupCommands.makeUnique(node.id, in: .root, of: content, registry: testRegistry)
        try content.apply(edit.command, registry: testRegistry)
        let copy = try #require(content.definitions.values.first { $0.id != doubler.id })
        let copiedAdd = try #require(copy.graph.nodes.values.first { $0.typeID == AddNode.typeID })
        let copiedWires: Set = [Endpoint(node: copiedAdd.id, socket: "a"), Endpoint(node: copiedAdd.id, socket: "b")]
        #expect(copy.graph.ties[inner.id]?.wires == copiedWires)
        #expect(content.definitions[doubler.id]?.graph.ties == [inner.id: inner], "the original keeps its own")
    }
}
