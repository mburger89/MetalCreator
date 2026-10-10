import CreatorKernel
import Testing
@testable import CreatorGraph

/// Ungroup and Make Unique where the group node sits inside a definition, where an output fans out, and where a pick
/// names a face through two levels of group nodes (groups spec §5). `UngroupTests` has the top-level cases.
@MainActor
struct NestedGroupEditTests {
    let doubler = Doubler()

    func document(_ nodes: [Node], _ links: [Link] = [], _ definitions: [GroupDefinition]) -> DocumentModel {
        var start = graph(nodes, links)
        start.sortLinks()
        return DocumentModel(file: GraphFile(graph: start, definitions: table(definitions)), registry: testRegistry,
                             kernel: FakeKernel())
    }

    func perform(_ edit: GroupEdit, on document: DocumentModel) throws -> GroupEdit {
        try document.perform(edit.command)
        return edit
    }

    func count(_ content: GraphContent, _ id: NodeID) async throws -> Double? {
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: [id])
        return report.results[id]?.outputs?["count"]?.numbers?.first
    }

    /// "Outer": a definition that places `inner` once and puts out its `result`.
    func outer(placing inner: Node) -> GroupDefinition {
        define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
            [link(inner, "result", output, "result")]
        }
    }

    @Test func ungroupingInsideADefinitionSplicesIntoThatDefinitionOnly() async throws {
        let inner = instance(of: doubler.definition, ["value": .number(4)])
        let outer = outer(placing: inner)
        let top = instance(of: outer, output: true)
        let document = document([top], [], [doubler.definition, outer])
        let before = document.content
        let edit = try GroupCommands.ungroup(inner.id, in: .definition(outer.id), of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        let spliced = try #require(document.definitions[outer.id]).graph
        let add = try #require(edit.selection.first.flatMap { spliced.nodes[$0] })
        #expect(add.typeID == AddNode.typeID && add.inputValues == ["a": .number(4), "b": .number(4)])
        #expect(spliced.nodes[inner.id] == nil, "the group node is gone from Outer")
        let output = try #require(document.definitions[outer.id]?.outputNode)
        #expect(spliced.links.contains(link(add, "sum", output, "result")))
        #expect(document.definitions[doubler.id] == nil, "its last group node went with it")
        #expect(document.graph.nodes[top.id] == top, "the top level is untouched")
        await document.waitForEvaluation()
        #expect(document.results[top.id]?.outputs?["result"]?.numbers == [8])
        document.undo()
        #expect(document.content == before)
    }

    @Test func makeUniqueInsideADefinitionRetargetsThatGroupNodeOnly() async throws {
        let inner = instance(of: doubler.definition, ["value": .number(4)])
        let outer = outer(placing: inner)
        let beside = instance(of: doubler.definition, ["value": .number(1)], output: true)
        let top = instance(of: outer, output: true)
        let document = document([top, beside], [], [doubler.definition, outer])
        let before = document.content
        let edit = try GroupCommands.makeUnique(inner.id, in: .definition(outer.id), of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        let copy = try #require(document.definitions.values.first { $0.name == "Doubler 2" })
        #expect(edit.selection == [inner.id])
        #expect(document.definitions[outer.id]?.graph.nodes[inner.id]?.inputValues[NodeSetting.group] == .group(copy.id))
        #expect(document.definitions[outer.id]?.graph.nodes[inner.id]?.name == "Doubler 2")
        #expect(document.graph.nodes[beside.id]?.inputValues[NodeSetting.group] == .group(doubler.id), "the other keeps the original")
        await document.waitForEvaluation()
        #expect(document.results[top.id]?.outputs?["result"]?.numbers == [8])
        #expect(document.results[beside.id]?.outputs?["result"]?.numbers == [2])
        document.undo()
        #expect(document.content == before)
    }

    @Test func ungroupingAnOutputThatFansOutFeedsEveryTakerFromTheSameInnerSocket() async throws {
        let node = instance(of: doubler.definition, ["value": .number(3)])
        let first = makeNode(SinkNode.self, output: true), second = makeNode(SinkNode.self, output: true)
        let document = document([node, first, second],
                                [link(node, "result", first, "value"), link(node, "result", second, "value")], [doubler.definition])
        let edit = try perform(try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        let add = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(Set(document.graph.links) == [link(add, "sum", first, "value"), link(add, "sum", second, "value")])
        await document.waitForEvaluation()
        #expect(document.results[first.id]?.outputs?["value"]?.numbers == [6])
        #expect(document.results[second.id]?.outputs?["value"]?.numbers == [6])
    }

    /// "Wrapped": a group node of "Capped" (a box) inside "Wrapper", both taking the box's solid out; a counter at the top
    /// level picks the end cap of that box by the name it has through the two group nodes.
    struct ChainScene {
        var content: GraphContent
        let box: Node
        let inner: Node
        let outer: Node
        let counter: Node
    }

    func chainScene() -> ChainScene {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        let capped = define("Capped", outputs: [SocketSpec("solid", .solid)], nodes: [box]) { _, output in
            [link(box, "solid", output, "solid")]
        }
        let inner = instance(of: capped)
        let wrapper = define("Wrapper", outputs: [SocketSpec("solid", .solid)], nodes: [inner]) { _, output in
            [link(inner, "solid", output, "solid")]
        }
        let outer = instance(of: wrapper)
        var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
        counter.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([outer.id, inner.id, box.id]))
        let content = GraphContent(graph: graph([outer, counter], [link(outer, "solid", counter, "solid")]),
                                   definitions: table([capped, wrapper]))
        return ChainScene(content: content, box: box, inner: inner, outer: outer, counter: counter)
    }

    @Test func ungroupRenamesAPickThroughTwoLevelsOfGroups() async throws {
        let scene = chainScene()
        var content = scene.content
        #expect(try await count(content, scene.counter.id) == 1)
        let edit = try GroupCommands.ungroup(scene.outer.id, in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let spliced = try #require(edit.selection.first)
        #expect(spliced != scene.inner.id, "the inner group node comes out under a new ID")
        #expect(content.graph.nodes[scene.counter.id]?.inputValues[NodeSetting.face]
                == endCapPick(of: NodeID.scoped([spliced, scene.box.id])), "now one group node deep")
        #expect(try await count(content, scene.counter.id) == 1)
    }

    @Test func makeUniqueRenamesAPickThroughTwoLevelsOfGroups() async throws {
        let scene = chainScene()
        var content = scene.content
        let edit = try GroupCommands.makeUnique(scene.outer.id, in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let copy = try #require(content.definitions.values.first { $0.name == "Wrapper 2" })
        let copiedInner = try #require(copy.graph.nodes.values.first { $0.typeID == GroupNodes.groupTypeID })
        #expect(copiedInner.id != scene.inner.id)
        #expect(content.graph.nodes[scene.counter.id]?.inputValues[NodeSetting.face]
                == endCapPick(of: NodeID.scoped([scene.outer.id, copiedInner.id, scene.box.id])))
        #expect(try await count(content, scene.counter.id) == 1)
    }
}
