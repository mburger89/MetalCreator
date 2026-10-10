import CreatorKernel
import Testing
@testable import CreatorGraph

/// The document holds its group definitions, edits them through `perform`, saves them and evaluates group nodes
/// (groups spec §4, §5).
@MainActor
struct DocumentModelGroupTests {
    let doubler = Doubler()

    func model(_ nodes: [Node], _ definitions: [GroupDefinition]) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph(nodes), definitions: table(definitions)), registry: testRegistry,
                      kernel: FakeKernel())
    }

    @Test func groupNodesEvaluateAndTheRegistryCarriesTheDefinitions() async {
        let node = instance(of: doubler.definition, ["value": .number(4)], output: true)
        let document = model([node], [doubler.definition])
        await document.waitForEvaluation()
        #expect(document.definitions == table([doubler.definition]))
        #expect(document.registry.inputs(for: node) == doubler.definition.inputs)
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [8])
    }

    @Test func anEditInsideADefinitionReevaluatesItsGroupNodesAndUndoes() async throws {
        let node = instance(of: doubler.definition, ["value": .number(4)], output: true)
        let document = model([node], [doubler.definition])
        await document.waitForEvaluation()
        let wire = link(doubler.input, "value", doubler.add, "b")
        try document.perform(.batch([.disconnect(wire), .setInput(doubler.add.id, "b", .number(10))]),
                             at: .definition(doubler.id))
        #expect(document.results[node.id]?.state == .evaluating)
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [14])
        #expect(document.definitions[doubler.id]?.graph.links.contains(wire) == false)
        document.undo()
        await document.waitForEvaluation()
        #expect(document.definitions == table([doubler.definition]))
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [8])
        document.redo()
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [14])
    }

    @Test func definitionsAreSavedAndReopened() async throws {
        let node = instance(of: doubler.definition, output: true)
        let document = model([node], [doubler.definition])
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.content == document.content)
        await reopened.waitForEvaluation()
        #expect(reopened.results[node.id]?.outputs?["result"]?.numbers == [2])
    }

    @Test func aRefusedGroupEditLeavesNoUndoStep() {
        let document = model([], [doubler.definition])
        #expect(throws: GraphError.invalidValue("An Output node can't go in a group.")) {
            try document.perform(.addNode(makeNode(SinkNode.self)), at: .definition(doubler.id))
        }
        #expect(!document.canUndo)
    }

    @Test func renamesRefreshTheGroupsMessageWithoutMarkingItStale() async throws {
        let warn = makeNode(WarnNode.self)
        let warner = define("Warner", outputs: [SocketSpec("value", .number)], nodes: [warn]) { _, output in
            [link(warn, "value", output, "value")]
        }
        let node = instance(of: warner, output: true)
        let document = model([node], [warner])
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Warner › Warn: Careful"))
        #expect(document.innerResults[[node.id, warn.id]]?.state == .warning("Careful"), "inner results are kept")

        try document.perform(.inDefinition(warner.id, .rename(warn.id, "Check")))
        #expect(document.results[node.id]?.state == .warning("Warner › Warn: Careful"), "not marked evaluating")
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Warner › Check: Careful"))
        var interface = warner.interface
        interface.name = "Checker"
        try document.perform(.setInterface(warner.id, interface))
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Checker › Check: Careful"))

        // A new accent changes no result and no message: nothing re-evaluates.
        interface.accent = .green
        try document.perform(.setInterface(warner.id, interface))
        #expect(!document.isEvaluating)
        document.undo()
        #expect(!document.isEvaluating)
        document.undo()
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Warner › Check: Careful"))
    }
}
