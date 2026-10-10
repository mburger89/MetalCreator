import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Group (⌘G, groups spec §5).
@MainActor
struct GroupCommandTests {
    let scene = GroupScene()

    func document(_ extra: [Node] = []) -> DocumentModel {
        var start = graph(scene.nodes + extra, scene.links)
        start.sortLinks()  // As a loaded file has them, so undo compares equal.
        return DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
    }

    func group(_ ids: Set<NodeID>, in document: DocumentModel, at path: GraphPath = .root) throws -> GroupEdit {
        let edit = try GroupCommands.group(ids, in: path, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        return edit
    }

    @Test func groupingMovesTheNodesIntoANewDefinitionAndWiresTheBoundary() async throws {
        let document = document()
        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
        let edit = try group([scene.a1.id, scene.a2.id], in: document)

        let definition = try #require(document.definitions.values.first)
        #expect(definition.name == "Group")
        #expect(definition.inputs == [SocketSpec("a", .number), SocketSpec("b", .number)])
        #expect(definition.outputs == [SocketSpec("sum", .number), SocketSpec("sum2", .number)])
        #expect(definition.graph.nodes[scene.a1.id]?.position == Vector2(0, 0))
        #expect(definition.graph.nodes[scene.a2.id]?.position == Vector2(0, 100))
        #expect(definition.inputNode?.position == Vector2(-240, 0))
        #expect(definition.outputNode?.position == Vector2(240, 0))
        let input = try #require(definition.inputNode), output = try #require(definition.outputNode)
        #expect(Set(definition.graph.links) == [
            link(input, "a", scene.a1, "a"), link(input, "a", scene.a1, "b"), link(input, "b", scene.a2, "b"),
            link(scene.a1, "sum", scene.a2, "a"), link(scene.a1, "sum", output, "sum"), link(scene.a2, "sum", output, "sum2"),
        ])

        let node = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(edit.selection.count == 1)
        #expect(node.typeID == GroupNodes.groupTypeID && node.name == "Group" && node.position == Vector2(200, 0))
        #expect(document.graph.nodes[scene.a1.id] == nil && document.graph.nodes[scene.a2.id] == nil)
        #expect(Set(document.graph.links) == [
            link(scene.c1, "value", node, "a"), link(scene.c2, "value", node, "b"),
            link(node, "sum2", scene.sink, "value"), link(node, "sum", scene.other, "a"),
        ])

        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
    }

    @Test func groupingIsOneUndoStep() throws {
        let document = document()
        let before = document.content
        _ = try group([scene.a1.id, scene.a2.id], in: document)
        document.undo()
        #expect(document.content == before)
        document.redo()
        #expect(document.definitions.count == 1)
    }

    @Test func eachNewDefinitionGetsTheNextName() throws {
        let document = document()
        _ = try group([scene.a1.id], in: document)
        _ = try group([scene.a2.id], in: document)
        #expect(Set(document.definitions.values.map(\.name)) == ["Group", "Group 2"])
    }

    @Test func groupingInsideADefinitionNestsAGroup() async throws {
        let doubler = Doubler()
        let node = instance(of: doubler.definition, ["value": .number(5)], output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([node]), definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let edit = try group([doubler.add.id], in: document, at: .definition(doubler.id))
        let inner = try #require(document.definitions.values.first { $0.id != doubler.id })
        #expect(inner.inputs.map(\.name) == ["a"], "Group Input's one source feeds both of Add's inputs")
        #expect(document.definitions[doubler.id]?.graph.nodes[edit.selection.first ?? NodeID()]?.typeID == GroupNodes.groupTypeID)
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [10])
    }

    @Test func oneSourceWiredOutTwiceIsOneOutput() throws {
        let second = GroupScene.position(makeNode(AddNode.self), 400, 300)
        var start = graph(scene.nodes + [second], scene.links + [link(scene.a2, "sum", second, "a")])
        start.sortLinks()
        let document = DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
        let edit = try group([scene.a2.id], in: document)
        let node = try #require(edit.selection.first)
        #expect(document.definitions.values.first?.outputs.map(\.name) == ["sum"])
        let fromGroup = Endpoint(node: node, socket: "sum")
        #expect(document.graph.incomingLink(to: Endpoint(node: scene.sink.id, socket: "value"))?.from == fromGroup)
        #expect(document.graph.incomingLink(to: Endpoint(node: second.id, socket: "a"))?.from == fromGroup)
    }

    @Test func groupingAGroupNodeNestsItAndKeepsTheResult() async throws {
        let document = document()
        let first = try group([scene.a1.id, scene.a2.id], in: document)
        let inner = try #require(first.selection.first)
        let outer = try group([inner], in: document)
        let outerNode = try #require(outer.selection.first.flatMap { document.graph.nodes[$0] })
        let outerDefinition = try #require(document.registry.group(of: outerNode))
        #expect(outerDefinition.graph.nodes[inner]?.typeID == GroupNodes.groupTypeID)
        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
    }

    @Test func socketAndDefinitionNamesAreMadeUnique() {
        #expect(GroupNaming.uniqueSocketName("a", among: ["a", "a2"]) == "a3")
        #expect(GroupNaming.uniqueSocketName(NodeSetting.group, among: []) == "groupID2")
        #expect(GroupNaming.uniqueSocketName("projection.e1", among: []) == "projection.e12")
        #expect(GroupNaming.uniqueSocketName("b", among: ["a"]) == "b")
        let doubler = Doubler(name: "Group")
        #expect(GroupNaming.uniqueDefinitionName("Group", among: table([doubler.definition])) == "Group 2")
        #expect(GroupNaming.uniqueDefinitionName("Rib", among: table([doubler.definition])) == "Rib")
    }

    @Test func groupingIsRefusedPlainly() {
        let document = document()
        let doubler = Doubler()
        let content = GraphContent(graph: document.graph, definitions: table([doubler.definition]))
        #expect(throws: GraphError.invalidValue("Select the nodes to group.")) {
            try GroupCommands.group([], in: .root, of: content, registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("An Output node can't go in a group.")) {
            try GroupCommands.group([scene.a2.id, scene.sink.id], in: .root, of: content, registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("Group Input and Group Output can't go in a group.")) {
            try GroupCommands.group([doubler.input.id, doubler.add.id], in: .definition(doubler.id), of: content,
                                    registry: testRegistry)
        }
        var mystery = GroupScene.position(makeNode(ConstantNode.self), -200, 0)
        mystery.typeID = "missing.type"
        var withMystery = content
        withMystery.graph.nodes[mystery.id] = mystery
        withMystery.graph.links.append(link(mystery, "value", scene.a1, "a"))
        withMystery.graph.links.removeAll { $0 == link(scene.c1, "value", scene.a1, "a") }
        #expect(throws: GraphError.invalidValue(
            "A wire into the selection comes from a socket of unknown type, so it can't become an input.")) {
            try GroupCommands.group([scene.a1.id], in: .root, of: withMystery, registry: testRegistry)
        }
    }

    /// The counts of `ids`' `count` outputs after evaluating `content` with the face pick counter registered.
    func counts(_ content: GraphContent, _ ids: [NodeID]) async throws -> [Double?] {
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: Set(ids))
        return ids.map { report.results[$0]?.outputs?["count"]?.numbers?.first }
    }

    @Test func groupingRenamesThePicksOnTheGroupedNodesFaces() async throws {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        var inside = pickRegistry.makeNode(FacePickCountNode.typeID), outside = pickRegistry.makeNode(FacePickCountNode.typeID)
        inside.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        outside.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        var unrelated = pickRegistry.makeNode(FacePickCountNode.typeID)
        unrelated.inputValues[NodeSetting.face] = endCapPick(of: outside.id)
        let sink = pickRegistry.makeNode(SinkNode.typeID)  // So the inside counter's count is an output of the group.
        var content = GraphContent(graph: graph([box, inside, outside, unrelated, sink], [
            link(box, "solid", inside, "solid"), link(box, "solid", outside, "solid"), link(inside, "count", sink, "value"),
        ]))
        #expect(try await counts(content, [inside.id, outside.id]) == [1, 1])

        let edit = try GroupCommands.group([box.id, inside.id], in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let node = try #require(edit.selection.first)
        let definition = try #require(content.definitions.values.first)
        #expect(content.graph.nodes[outside.id]?.inputValues[NodeSetting.face] == endCapPick(of: NodeID.scoped([node, box.id])))
        #expect(definition.graph.nodes[inside.id]?.inputValues[NodeSetting.face] == endCapPick(of: box.id),
                "a pick inside the selection names its nodes as before")
        #expect(content.graph.nodes[unrelated.id]?.inputValues[NodeSetting.face] == endCapPick(of: outside.id))
        #expect(try await counts(content, [outside.id]) == [1])
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: [node])
        #expect(report.innerResults[[node, inside.id]]?.outputs?["count"]?.numbers == [1])
    }

    @Test func groupingInsideADefinitionRenamesPicksThroughEachInstance() async throws {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        let boxer = define("Boxer", outputs: [SocketSpec("solid", .solid)], nodes: [box]) { _, output in
            [link(box, "solid", output, "solid")]
        }
        let first = instance(of: boxer), second = instance(of: boxer)
        var counters: [Node] = []
        for placed in [first, second] {
            var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
            counter.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([placed.id, box.id]))
            counters.append(counter)
        }
        var content = GraphContent(graph: graph([first, second] + counters, [
            link(first, "solid", counters[0], "solid"), link(second, "solid", counters[1], "solid"),
        ]), definitions: table([boxer]))
        #expect(try await counts(content, counters.map(\.id)) == [1, 1])

        let edit = try GroupCommands.group([box.id], in: .definition(boxer.id), of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let node = try #require(edit.selection.first)
        #expect(content.graph.nodes[counters[0].id]?.inputValues[NodeSetting.face]
            == endCapPick(of: NodeID.scoped([first.id, node, box.id])))
        #expect(try await counts(content, counters.map(\.id)) == [1, 1])
    }
}
