import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Ungroup and Make Unique (groups spec §5).
@MainActor
struct UngroupTests {
    let scene = GroupScene()
    let doubler = Doubler()

    func document(_ nodes: [Node], _ links: [Link] = [], _ definitions: [GroupDefinition] = []) -> DocumentModel {
        var start = graph(nodes, links)
        start.sortLinks()
        return DocumentModel(file: GraphFile(graph: start, definitions: table(definitions)), registry: testRegistry,
                             kernel: FakeKernel())
    }

    func perform(_ edit: GroupEdit, on document: DocumentModel) throws -> GroupEdit {
        try document.perform(edit.command)
        return edit
    }

    @Test func ungroupingPutsTheNodesBackWithNewIDs() async throws {
        let document = document(scene.nodes, scene.links)
        let before = document.content
        let grouped = try perform(try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content,
                                                          registry: testRegistry), on: document)
        let node = try #require(grouped.selection.first)
        let edit = try perform(try GroupCommands.ungroup(node, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        #expect(document.definitions.isEmpty, "its last group node is gone")
        #expect(edit.selection.count == 2)
        #expect(edit.selection.isDisjoint(with: [scene.a1.id, scene.a2.id]))
        let spliced = edit.selection.compactMap { document.graph.nodes[$0] }
        #expect(Set(spliced.map(\.position)) == [Vector2(200, 0), Vector2(200, 100)])
        #expect(document.graph.links.count == scene.links.count)
        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
        document.undo()
        document.undo()
        #expect(document.content == before)
    }

    @Test func anUnwiredInputsValueLandsOnTheInnerInputs() async throws {
        let node = instance(of: doubler.definition, ["value": .number(4)])
        let sink = makeNode(SinkNode.self, output: true)
        let document = document([node, sink], [link(node, "result", sink, "value")], [doubler.definition])
        let edit = try perform(try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        let add = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(add.inputValues == ["a": .number(4), "b": .number(4)])
        #expect(document.graph.links == [Link(from: Endpoint(node: add.id, socket: "sum"), to: Endpoint(node: sink.id, socket: "value"))])
        await document.waitForEvaluation()
        #expect(document.results[sink.id]?.outputs?["value"]?.numbers == [8])
    }

    @Test func aStraightThroughWireJoinsWhatFedItToWhatItFed() throws {
        let pass = define("Pass", inputs: [SocketSpec("x", .number)], outputs: [SocketSpec("y", .number)], nodes: []) { input, output in
            [link(input, "x", output, "y")]
        }
        let constant = makeNode(ConstantNode.self), wired = instance(of: pass), typed = instance(of: pass, ["x": .number(5)])
        let first = makeNode(SinkNode.self, output: true), second = makeNode(SinkNode.self, output: true)
        let document = document([constant, wired, typed, first, second],
                                [link(constant, "value", wired, "x"), link(wired, "y", first, "value"), link(typed, "y", second, "value")],
                                [pass])
        _ = try perform(try GroupCommands.ungroup(wired.id, in: .root, of: document.content, registry: testRegistry), on: document)
        let fed = document.graph.incomingLink(to: Endpoint(node: first.id, socket: "value"))?.from
        #expect(fed == Endpoint(node: constant.id, socket: "value"))
        #expect(document.definitions[pass.id] != nil, "another group node still uses it")
        _ = try perform(try GroupCommands.ungroup(typed.id, in: .root, of: document.content, registry: testRegistry), on: document)
        #expect(document.graph.nodes[second.id]?.inputValues["value"] == .number(5))
        #expect(document.definitions.isEmpty)
    }

    @Test func onlyAGroupNodeUngroups() {
        let content = GraphContent(graph: graph([scene.c1]))
        #expect(throws: GraphError.invalidValue("Select one group node to ungroup.")) {
            try GroupCommands.ungroup(scene.c1.id, in: .root, of: content, registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("Select one group node to make unique.")) {
            try GroupCommands.makeUnique(scene.c1.id, in: .root, of: content, registry: testRegistry)
        }
    }

    @Test func makeUniqueGivesOneGroupNodeItsOwnCopy() async throws {
        let kept = instance(of: doubler.definition, ["value": .number(1)], output: true)
        let split = instance(of: doubler.definition, ["value": .number(1)], output: true)
        let document = document([kept, split], [], [doubler.definition])
        let before = document.content
        let edit = try perform(try GroupCommands.makeUnique(split.id, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        #expect(edit.selection == [split.id])
        let copy = try #require(document.definitions.values.first { $0.id != doubler.id })
        #expect(copy.name == "Doubler 2" && copy.inputs == doubler.definition.inputs && copy.outputs == doubler.definition.outputs)
        #expect(Set(copy.graph.nodes.keys).isDisjoint(with: doubler.definition.graph.nodes.keys))
        #expect(copy.graph.nodes.count == 3 && copy.graph.links.count == 3)
        #expect(copy.inputNode?.inputValues[NodeSetting.group] == .group(copy.id))
        #expect(document.graph.nodes[split.id]?.inputValues[NodeSetting.group] == .group(copy.id))
        #expect(document.graph.nodes[split.id]?.name == "Doubler 2")

        let add = try #require(copy.graph.nodes.values.first { $0.typeID == AddNode.typeID })
        let wire = try #require(copy.graph.incomingLink(to: Endpoint(node: add.id, socket: "b")))
        try document.perform(.batch([.disconnect(wire), .setInput(add.id, "b", .number(10))]), at: .definition(copy.id))
        await document.waitForEvaluation()
        #expect(document.results[kept.id]?.outputs?["result"]?.numbers == [2])
        #expect(document.results[split.id]?.outputs?["result"]?.numbers == [11])
        document.undo()
        document.undo()
        #expect(document.content == before)
    }

    /// "Counted": a box whose end cap a counter inside picks; it puts out the box's solid and the count. One group
    /// node of it, and a counter outside picking that node's box's end cap.
    struct CountedScene {
        var content: GraphContent
        let box: Node
        let counter: Node
        let node: Node
        let outside: Node
    }

    func countedScene() -> CountedScene {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
        counter.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        let counted = define("Counted", outputs: [SocketSpec("count", .number), SocketSpec("solid", .solid)],
                             nodes: [box, counter]) { _, output in
            [link(box, "solid", counter, "solid"), link(counter, "count", output, "count"), link(box, "solid", output, "solid")]
        }
        let node = instance(of: counted)
        var outside = pickRegistry.makeNode(FacePickCountNode.typeID)
        outside.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([node.id, box.id]))
        let content = GraphContent(graph: graph([node, outside], [link(node, "solid", outside, "solid")]),
                                   definitions: table([counted]))
        return CountedScene(content: content, box: box, counter: counter, node: node, outside: outside)
    }

    func count(_ content: GraphContent, _ path: [NodeID]) async throws -> Double? {
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: [path[0]])
        let result = path.count == 1 ? report.results[path[0]] : report.innerResults[path]
        return result?.outputs?["count"]?.numbers?.first
    }

    @Test func ungroupRenamesThePicksOnTheSplicedNodesFaces() async throws {
        let counted = countedScene()
        var content = counted.content
        let (box, counter, node, outside) = (counted.box, counted.counter, counted.node, counted.outside)
        #expect(try await count(content, [outside.id]) == 1)
        let edit = try GroupCommands.ungroup(node.id, in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let spliced = try #require(content.graph.nodes.values.first { $0.typeID == BoxNode.typeID })
        let splicedCounter = try #require(content.graph.nodes.values.first { $0.id != outside.id && $0.typeID == FacePickCountNode.typeID })
        #expect(spliced.id != box.id && splicedCounter.id != counter.id)
        #expect(content.graph.nodes[outside.id]?.inputValues[NodeSetting.face] == endCapPick(of: spliced.id))
        #expect(splicedCounter.inputValues[NodeSetting.face] == endCapPick(of: spliced.id))
        #expect(try await count(content, [outside.id]) == 1)
        #expect(try await count(content, [splicedCounter.id]) == 1)
    }

    @Test func makeUniqueRenamesThePicksOnTheCopysFaces() async throws {
        let counted = countedScene()
        var content = counted.content
        let (box, node, outside) = (counted.box, counted.node, counted.outside)
        let edit = try GroupCommands.makeUnique(node.id, in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let copy = try #require(content.definitions.values.first { $0.name == "Counted 2" })
        let copyBox = try #require(copy.graph.nodes.values.first { $0.typeID == BoxNode.typeID })
        let copyCounter = try #require(copy.graph.nodes.values.first { $0.typeID == FacePickCountNode.typeID })
        #expect(copyBox.id != box.id)
        #expect(content.graph.nodes[outside.id]?.inputValues[NodeSetting.face] == endCapPick(of: NodeID.scoped([node.id, copyBox.id])))
        #expect(copyCounter.inputValues[NodeSetting.face] == endCapPick(of: copyBox.id))
        #expect(try await count(content, [outside.id]) == 1)
        #expect(try await count(content, [node.id, copyCounter.id]) == 1)
    }
}
