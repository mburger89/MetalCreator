import CreatorKernel
import Testing
@testable import CreatorGraph

/// Exposing a socket by wiring it to the "+" of Group Input or Group Output (groups spec §6): one command, one undo
/// step.
@MainActor
struct GroupExposeTests {
    /// "Rib": an Add whose `a` Group Input feeds; `b` is unwired (default 0, millimetres is not set on the test node).
    let add = makeNode(AddNode.self)
    let definition: GroupDefinition

    init() {
        let add = self.add
        definition = define("Rib", inputs: [SocketSpec("a", .number)], outputs: [], nodes: [add]) { input, _ in
            [link(input, "a", add, "a")]
        }
    }

    func document(_ group: Node) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph([group]), definitions: table([definition])), registry: testRegistry,
                      kernel: FakeKernel())
    }

    @Test func droppingAWireOnGroupOutputsPlusExposesAnOutputInOneStep() throws {
        let group = instance(of: definition)
        let document = document(group)
        let output = try #require(definition.outputNode)
        let command = try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: output.id,
                                                     in: definition.id, of: document.content, registry: testRegistry)
        try document.perform(command)
        let exposed = try #require(document.definitions[definition.id])
        #expect(exposed.outputs == [SocketSpec("sum", .number)])
        #expect(exposed.graph.links.contains(link(add, "sum", output, "sum")))
        #expect(document.registry.outputs(for: group).map(\.name) == ["sum"], "the group node has it too")
        document.undo()
        #expect(document.definitions == table([definition]), "one undo step takes the socket and its wire")
        #expect(!document.canUndo)
    }

    @Test func aSecondDropFromTheSameSocketGetsAnotherName() throws {
        let document = document(instance(of: definition))
        let output = try #require(definition.outputNode)
        for _ in 0..<2 {
            let command = try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: output.id,
                                                         in: definition.id, of: document.content, registry: testRegistry)
            try document.perform(command)
        }
        #expect(document.definitions[definition.id]?.outputs.map(\.name) == ["sum", "sum2"])
    }

    @Test func draggingFromGroupInputsPlusOntoAnInputExposesAnInputWithItsDefault() throws {
        let group = instance(of: definition)
        let document = document(group)
        let input = try #require(definition.inputNode)
        let command = try GroupCommands.exposeInput(to: Endpoint(node: add.id, socket: "b"), from: input.id,
                                                    in: definition.id, of: document.content, registry: testRegistry)
        try document.perform(command)
        let exposed = try #require(document.definitions[definition.id])
        let spec = try #require(exposed.inputs.last)
        let target = try #require(AddNode.inputs.first { $0.name == "b" })
        #expect(spec.name == "b" && spec.type == .number && spec.defaultValue == target.defaultValue)
        #expect(exposed.graph.links.contains(link(input, "b", add, "b")))
        #expect(document.registry.inputs(for: group).map(\.name) == ["a", "b"])
        document.undo()
        #expect(document.definitions == table([definition]))
    }

    @Test func aDropIsRefusedForABoundaryOfAnotherDefinitionOrASocketThatIsntThere() throws {
        let document = document(instance(of: definition))
        let input = try #require(definition.inputNode), output = try #require(definition.outputNode)
        let content = document.content
        #expect(throws: GroupRefusal.boundaryCount) {
            try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: input.id, in: definition.id,
                                           of: content, registry: testRegistry)
        }
        #expect(throws: GroupRefusal.missing) {
            try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: output.id, in: GroupID(),
                                           of: content, registry: testRegistry)
        }
        #expect(throws: GroupCommands.missingSocket) {
            try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "nothing"), on: output.id,
                                           in: definition.id, of: content, registry: testRegistry)
        }
        #expect(throws: GroupCommands.missingSocket) {
            try GroupCommands.exposeInput(to: Endpoint(node: add.id, socket: "nothing"), from: input.id,
                                          in: definition.id, of: content, registry: testRegistry)
        }
    }
}
