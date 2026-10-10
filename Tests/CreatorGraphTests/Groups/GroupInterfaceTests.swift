import CreatorKernel
import Testing
@testable import CreatorGraph

/// Definition edits (groups spec §5): rename, accent, sockets and delete, each one undo step.
@MainActor
struct GroupInterfaceTests {
    let doubler = Doubler()

    /// A constant wired into one Doubler, a typed value on another, and both results taken by sinks.
    @MainActor
    struct Setup {
        let constant = makeNode(ConstantNode.self, ["value": .number(3)])
        let wired: Node
        let typed: Node
        let first = makeNode(SinkNode.self, output: true)
        let second = makeNode(SinkNode.self, output: true)
        let document: DocumentModel

        init(_ doubler: Doubler) {
            wired = instance(of: doubler.definition)
            typed = instance(of: doubler.definition, ["value": .number(4)])
            var start = graph([constant, wired, typed, first, second], [
                link(constant, "value", wired, "value"), link(wired, "result", first, "value"), link(typed, "result", second, "value"),
            ])
            start.sortLinks()
            document = DocumentModel(file: GraphFile(graph: start, definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        }
    }

    @Test func renamingADefinitionRenamesTheGroupNodesNamedAfterIt() throws {
        let setup = Setup(doubler)
        try setup.document.perform(.rename(setup.typed.id, "Mine"))
        let before = setup.document.content
        try setup.document.perform(try GroupCommands.rename(doubler.id, to: "Twice", in: setup.document.content))
        #expect(setup.document.definitions[doubler.id]?.name == "Twice")
        #expect(setup.document.graph.nodes[setup.wired.id]?.name == "Twice")
        #expect(setup.document.graph.nodes[setup.typed.id]?.name == "Mine")
        setup.document.undo()
        #expect(setup.document.content == before)
        let taken = Doubler(name: "Taken")
        try setup.document.perform(.addDefinition(taken.definition))
        #expect(throws: GraphError.invalidValue("A group named “Taken” already exists.")) {
            try setup.document.perform(try GroupCommands.rename(doubler.id, to: "Taken", in: setup.document.content))
        }
    }

    @Test func theAccentIsADefinitionEdit() throws {
        let setup = Setup(doubler)
        try setup.document.perform(try GroupCommands.setAccent(doubler.id, .orange, in: setup.document.content))
        #expect(setup.document.definitions[doubler.id]?.accent == .orange)
        setup.document.undo()
        #expect(setup.document.definitions[doubler.id]?.accent == .purple)
    }

    @Test func anAddedSocketGetsAFreeName() throws {
        let setup = Setup(doubler)
        let (command, name) = try GroupCommands.addSocket(doubler.id, side: .input, name: "value", type: .integer,
                                                          in: setup.document.content)
        try setup.document.perform(command)
        #expect(name == "value2")
        #expect(setup.document.registry.inputs(for: setup.wired).map(\.name) == ["value", "value2"])
        let (output, outputName) = try GroupCommands.addSocket(doubler.id, side: .output, name: "result", type: .solid,
                                                               in: setup.document.content)
        try setup.document.perform(output)
        #expect(outputName == "result2")
        #expect(setup.document.definitions[doubler.id]?.outputs.last == SocketSpec("result2", .solid))
    }

    @Test func renamingASocketKeepsItsWiresAndValues() async throws {
        let setup = Setup(doubler)
        let before = setup.document.content
        try setup.document.perform(try GroupCommands.renameSocket(doubler.id, side: .input, from: "value", to: "x",
                                                                  in: setup.document.content))
        try setup.document.perform(try GroupCommands.renameSocket(doubler.id, side: .output, from: "result", to: "out",
                                                                  in: setup.document.content))
        let document = setup.document
        #expect(document.graph.incomingLink(to: Endpoint(node: setup.wired.id, socket: "x"))?.from.node == setup.constant.id)
        #expect(document.graph.nodes[setup.typed.id]?.inputValues["x"] == .number(4))
        #expect(document.graph.nodes[setup.typed.id]?.inputValues["value"] == nil)
        #expect(document.graph.incomingLink(to: Endpoint(node: setup.first.id, socket: "value"))?.from.socket == "out")
        #expect(document.definitions[doubler.id]?.graph.links.filter { $0.from.node == doubler.input.id }.map(\.from.socket) == ["x", "x"])
        await document.waitForEvaluation()
        #expect(document.results[setup.first.id]?.outputs?["value"]?.numbers == [6])
        #expect(document.results[setup.second.id]?.outputs?["value"]?.numbers == [8])
        document.undo()
        document.undo()
        #expect(document.content == before)
        #expect(throws: GraphError.invalidValue("That socket no longer exists.")) {
            try GroupCommands.renameSocket(doubler.id, side: .input, from: "nope", to: "x", in: document.content)
        }
    }

    @Test func socketsReorder() throws {
        let setup = Setup(doubler)
        let (command, _) = try GroupCommands.addSocket(doubler.id, side: .input, name: "extra", type: .number, in: setup.document.content)
        try setup.document.perform(command)
        try setup.document.perform(try GroupCommands.moveSocket(doubler.id, side: .input, from: 1, to: 0, in: setup.document.content))
        #expect(setup.document.definitions[doubler.id]?.inputs.map(\.name) == ["extra", "value"])
        #expect(throws: GraphError.invalidValue("That socket no longer exists.")) {
            try GroupCommands.moveSocket(doubler.id, side: .input, from: 0, to: 5, in: setup.document.content)
        }
    }

    @Test func aWiredSocketCantBeRemoved() throws {
        let setup = Setup(doubler)
        #expect(throws: GraphError.invalidValue("“value” is wired on “Doubler”. Unwire it first.")) {
            try GroupCommands.removeSocket(doubler.id, side: .input, name: "value", in: setup.document.content)
        }
        #expect(throws: GraphError.invalidValue("“result” is wired on “Doubler”. Unwire it first.")) {
            try GroupCommands.removeSocket(doubler.id, side: .output, name: "result", in: setup.document.content)
        }
    }

    @Test func removingASocketDropsItsWiresInsideAndItsValues() async throws {
        let setup = Setup(doubler)
        let document = setup.document
        try document.perform(.disconnect(link(setup.constant, "value", setup.wired, "value")))
        try document.perform(try GroupCommands.removeSocket(doubler.id, side: .input, name: "value", in: document.content))
        #expect(document.definitions[doubler.id]?.inputs.isEmpty == true)
        #expect(document.definitions[doubler.id]?.graph.links == [link(doubler.add, "sum", doubler.output, "result")])
        #expect(document.graph.nodes[setup.typed.id]?.inputValues["value"] == nil)
        await document.waitForEvaluation()
        #expect(document.results[setup.second.id]?.outputs?["value"]?.numbers == [0], "Add's own defaults now")
    }

    @Test func onlyAnUnusedDefinitionIsDeleted() throws {
        let setup = Setup(doubler)
        #expect(throws: GraphError.invalidValue("“Doubler” is still in use. Delete its group nodes first.")) {
            try GroupCommands.deleteDefinition(doubler.id, in: setup.document.content)
        }
        let unused = Doubler(name: "Unused")
        try setup.document.perform(.addDefinition(unused.definition))
        try setup.document.perform(try GroupCommands.deleteDefinition(unused.id, in: setup.document.content))
        #expect(setup.document.definitions[unused.id] == nil)
        setup.document.undo()
        #expect(setup.document.definitions[unused.id] == unused.definition)
    }
}
