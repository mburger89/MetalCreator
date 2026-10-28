import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Pins follow Group, Ungroup and Make Unique (DIM-3 Task 3): a pin goes inside a new group with its node, as ties do, comes
/// back out on the spliced copy of its node, and Make Unique gives the copy pins on the copied nodes.
@MainActor
struct DimensionPinRemapTests {
    let scene = TieGraph()

    func pin(_ node: Node, _ socket: SocketName = "a") -> DimensionPin {
        DimensionPin(node: node.id, target: .input(socket))
    }

    func document(pins: [DimensionPin]) -> DocumentModel {
        var graph = scene.make()
        graph.dimensionPins = pins.sorted()
        return DocumentModel(file: GraphFile(graph: graph), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func groupingMovesAPinInsideWithItsNode() throws {
        let kept = pin(scene.s2)
        let moved = pin(scene.s1)
        let document = document(pins: [moved, kept])
        let before = document.content
        let edit = try GroupCommands.group([scene.c1.id, scene.c2.id, scene.s1.id], in: .root, of: document.content,
                                           registry: testRegistry)
        try document.perform(edit.command, name: UndoName.group)
        let definition = try #require(document.definitions.values.first)
        #expect(definition.graph.dimensionPins == [moved], "same node ID, now inside")
        #expect(document.graph.dimensionPins == [kept], "the top level loses it, and keeps the pin of a node left out")
        document.undo()
        #expect(document.content == before, "one undo step restores both")
    }

    @Test func ungroupingBringsAPinOutOnTheSplicedNode() throws {
        var doubler = Doubler()
        let inner = DimensionPin(node: doubler.add.id, target: .input("a"))
        doubler.definition.graph.dimensionPins = [inner]
        let node = instance(of: doubler.definition)
        let document = DocumentModel(file: GraphFile(graph: graph([node]), definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let edit = try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command, name: UndoName.ungroup)
        let add = try #require(edit.selection.compactMap { document.graph.nodes[$0] }.first { $0.typeID == AddNode.typeID })
        #expect(document.graph.dimensionPins == [DimensionPin(node: add.id, target: .input("a"))], "names the new node's ID")
        #expect(add.id != doubler.add.id)
        document.undo()
        #expect(document.graph.dimensionPins.isEmpty)
        #expect(document.definitions[doubler.id]?.graph.dimensionPins == [inner], "the definition keeps its own")
    }

    @Test func makeUniqueCopiesPinsOntoTheCopiedNodes() throws {
        var doubler = Doubler()
        let inner = DimensionPin(node: doubler.add.id, target: .input("b"))
        doubler.definition.graph.dimensionPins = [inner]
        let node = instance(of: doubler.definition)
        var content = GraphContent(graph: graph([node]), definitions: table([doubler.definition]))
        let edit = try GroupCommands.makeUnique(node.id, in: .root, of: content, registry: testRegistry)
        try content.apply(edit.command, registry: testRegistry)
        let copy = try #require(content.definitions.values.first { $0.id != doubler.id })
        let copiedAdd = try #require(copy.graph.nodes.values.first { $0.typeID == AddNode.typeID })
        #expect(copiedAdd.id != doubler.add.id)
        #expect(copy.graph.dimensionPins == [DimensionPin(node: copiedAdd.id, target: .input("b"))])
        #expect(content.definitions[doubler.id]?.graph.dimensionPins == [inner], "the original keeps its own")
    }
}
