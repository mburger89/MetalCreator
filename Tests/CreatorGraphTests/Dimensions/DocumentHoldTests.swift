import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

@MainActor
struct DocumentHoldTests {
    func makeNode(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:],
                  output: Bool = true) -> Node {
        var node = dimensionTestRegistry.makeNode(definition.typeID)
        node.inputValues = values
        node.isOutput = output
        return node
    }

    func model(_ nodes: [Node], _ links: [Link] = []) async -> DocumentModel {
        let document = DocumentModel(file: GraphFile(graph: graph(nodes, links)), registry: dimensionTestRegistry,
                                     kernel: FakeKernel())
        await document.waitForEvaluation()
        return document
    }

    func setValue(_ node: Node, _ value: Double) -> GraphCommand {
        .setInput(node.id, "value", .number(value))
    }

    @Test func aHeldDocumentKeepsShowingTheOldResults() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        document.holdResults()
        try document.perform(setValue(node, 20), name: UndoName.changeDimension)
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [10])
        #expect(document.results[node.id]?.state.isSuccess == true)
        #expect(document.lastGoodOutputs[node.id]?["value"]?.numbers == [10])
        document.releaseResults()
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [20])
        #expect(document.lastGoodOutputs[node.id]?["value"]?.numbers == [20])
    }

    @Test func whileCheckingNothingIsMarkedEvaluating() async throws {
        let node = makeNode(GatedNode.self, ["value": .number(1)])
        await GatedNode.gate.open()
        let document = await model([node])
        await GatedNode.gate.close()
        document.holdResults()
        try document.perform(setValue(node, 2), name: UndoName.changeDimension)
        guard case .ok = document.results[node.id]?.state else {
            Issue.record("expected .ok while checking, got \(String(describing: document.results[node.id]?.state))")
            return
        }
        await GatedNode.gate.open()
        await document.waitForEvaluation()
        document.releaseResults()
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [2])
    }

    @Test func aNewErrorDownstreamIsAProblem() async throws {
        let source = makeNode(ConstantNode.self, ["value": .number(10)], output: false)
        let threshold = makeNode(ThresholdNode.self)
        let document = await model([source, threshold], [link(source, "value", threshold, "value")])
        document.holdResults()
        try document.perform(setValue(source, 60), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        #expect(document.newProblem(in: step) == nil)  // the report has not arrived (or has no error yet)
        await document.waitForEvaluation()
        #expect(document.newProblem(in: step) == StepProblem(node: threshold.id, message: "Too big."))
    }

    @Test func warningsAreNotProblems() async throws {
        let node = makeNode(WarnNode.self, ["value": .number(1)])
        let document = await model([node])
        document.holdResults()
        try document.perform(setValue(node, 2), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        await document.waitForEvaluation()
        #expect(document.newProblem(in: step) == nil)
    }

    @Test func anErrorThatWasThereBeforeDoesNotRefuse() async throws {
        let source = makeNode(ConstantNode.self, ["value": .number(60)], output: false)
        let failing = makeNode(ThresholdNode.self)
        let unrelated = makeNode(ThresholdNode.self, ["value": .number(99)])
        let document = await model([source, failing, unrelated], [link(source, "value", failing, "value")])
        #expect(document.results[failing.id]?.state == .error("Too big."))
        document.holdResults()
        try document.perform(setValue(source, 70), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        await document.waitForEvaluation()
        #expect(!step.watched.contains(unrelated.id))
        #expect(step.watched.contains(failing.id))
        #expect(document.newProblem(in: step) == nil)
    }

    @Test func withdrawingRestoresContentAndHistoryWithNoRedo() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        try document.perform(setValue(node, 11), name: UndoName.changeDimension)
        document.undo()
        let before = document.content
        try document.perform(setValue(node, 60), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        #expect(document.withdraw(step))
        #expect(document.content == before)
        #expect(document.undoName == nil)
        #expect(document.redoName == UndoName.changeDimension)
        #expect(document.lastStep() == nil)
    }

    @Test func aSupersededStepIsNotWithdrawn() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        try document.perform(setValue(node, 20), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        document.undo()
        let after = document.content
        #expect(!document.withdraw(step))
        #expect(document.content == after)
        #expect(document.redoName == UndoName.changeDimension)
    }

    @Test func releaseAfterAThrowPublishesAgain() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        document.holdResults()
        #expect(throws: GraphError.self) { try document.perform(.setInput(NodeID(), "value", .number(1))) }
        document.releaseResults()
        #expect(!document.isHoldingResults)
        try document.perform(setValue(node, 20), name: UndoName.changeDimension)
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [20])
    }

    @Test func overlappingHoldsPublishOnlyWhenTheLastIsReleased() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        document.holdResults()
        document.holdResults()
        try document.perform(setValue(node, 20), name: UndoName.changeDimension)
        await document.waitForEvaluation()
        document.releaseResults()
        #expect(document.isHoldingResults)
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [10])
        document.releaseResults()
        #expect(!document.isHoldingResults)
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [20])
        document.releaseResults()  // unpaired: harmless
        #expect(!document.isHoldingResults)
    }

    @Test func aSecondStepJudgesAgainstTheHeldReportNotThePublishedOne() async throws {
        let source = makeNode(ConstantNode.self, ["value": .number(60)], output: false)
        let threshold = makeNode(ThresholdNode.self)
        let document = await model([source, threshold], [link(source, "value", threshold, "value")])
        document.holdResults()
        try document.perform(setValue(source, 5), name: UndoName.changeDimension)
        await document.waitForEvaluation()  // held: fine now, while the published result is still the error
        try document.perform(setValue(source, 70), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        #expect(step.errorsBefore[threshold.id] == nil)
    }

    @Test func aWithdrawnStepEvaluatesFromTheCache() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        document.holdResults()
        try document.perform(setValue(node, 60), name: UndoName.changeDimension)
        let step = try #require(document.lastStep())
        await document.waitForEvaluation()
        #expect(document.withdraw(step))
        await document.waitForEvaluation()
        #expect(document.heldReport?.evaluatedNodes.isEmpty == true)
        document.releaseResults()
        #expect(document.results[node.id]?.outputs?["value"]?.numbers == [10])
    }

    @Test func undoAndRedoForgetTheStep() async throws {
        let node = makeNode(ThresholdNode.self, ["value": .number(10)])
        let document = await model([node])
        try document.perform(setValue(node, 20), name: UndoName.changeDimension)
        #expect(document.lastStep() != nil)
        document.undo()
        #expect(document.lastStep() == nil)
        try document.perform(setValue(node, 30), name: UndoName.changeDimension)
        document.undo()
        document.redo()
        #expect(document.lastStep() == nil)
    }
}
