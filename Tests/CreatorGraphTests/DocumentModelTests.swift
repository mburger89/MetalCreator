import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

@MainActor
struct DocumentModelTests {
    func model(_ nodes: [Node], _ links: [Link] = []) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph(nodes, links)), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func outputsAreEvaluatedOnOpen() async {
        let a = makeNode(ConstantNode.self, ["value": .number(4)], output: true)
        let document = model([a])
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [4])
        #expect(!document.isEvaluating)
    }

    @Test func nonOutputNodesAreNotEvaluated() async {
        let a = makeNode(ConstantNode.self)
        let document = model([a])
        await document.waitForEvaluation()
        #expect(document.results[a.id] == nil)
    }

    @Test func previewNodeJoinsTheDemand() async {
        let a = makeNode(ConstantNode.self, ["value": .number(2)])
        let document = model([a])
        document.previewNode = a.id
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [2])
    }

    @Test func editsReevaluateAndUndoRestores() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(1)], output: true)
        let document = model([a])
        try document.perform(.setInput(a.id, "value", .number(9)))
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [9])
        document.undo()
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [1])
        #expect(document.canRedo)
    }

    @Test func lastGoodOutputSurvivesAnError() async throws {
        let box = makeNode(BoxNode.self, output: true)
        let document = model([box])
        await document.waitForEvaluation()
        #expect(document.lastGoodOutputs[box.id] != nil)
        try document.perform(.setInput(box.id, "distance", .number(-1)))
        await document.waitForEvaluation()
        guard case .error? = document.results[box.id]?.state else { Issue.record("expected error"); return }
        #expect(document.lastGoodOutputs[box.id] != nil)
    }

    @Test func staleEvaluationNeverOverwritesNewerResult() async throws {
        let slow = makeNode(SlowNode.self, ["value": .number(1)], output: true)
        let document = model([slow])
        for value in 2...6 {
            try document.perform(.setInput(slow.id, "value", .number(Double(value))), coalescingKey: "drag")
            try await Task.sleep(for: .milliseconds(20))
        }
        document.endCoalescing()
        await document.waitForEvaluation()
        #expect(document.results[slow.id]?.outputs?["value"]?.numbers == [6])
        document.undo()
        await document.waitForEvaluation()
        #expect(document.results[slow.id]?.outputs?["value"]?.numbers == [1])
    }

    @Test func deletingThePreviewNodeClearsThePreview() async throws {
        let a = makeNode(ConstantNode.self)
        let document = model([a])
        document.previewNode = a.id
        try document.perform(.removeNode(a.id))
        #expect(document.previewNode == nil)
        await document.waitForEvaluation()
        #expect(document.results[a.id] == nil)
    }

    @Test func editsMarkAffectedNodesAsEvaluating() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(1)], output: true)
        let document = model([a])
        await document.waitForEvaluation()
        try document.perform(.setInput(a.id, "value", .number(2)))
        #expect(document.results[a.id]?.state == .evaluating)
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.state.isSuccess == true)
    }

    @Test func removingANodeMarksItsDependentsEvaluating() async throws {
        let constant = makeNode(ConstantNode.self, ["value": .number(5)])
        let add = makeNode(AddNode.self, output: true)
        let document = model([constant, add], [link(constant, "value", add, "a")])
        await document.waitForEvaluation()
        #expect(document.results[add.id]?.outputs?["sum"]?.numbers == [5])
        try document.perform(.removeNode(constant.id))
        #expect(document.results[add.id]?.state == .evaluating)
        await document.waitForEvaluation()
        #expect(document.results[add.id]?.state.isSuccess == true)
        #expect(document.results[add.id]?.outputs?["sum"]?.numbers == [0])
    }

    @Test func refusedCommandLeavesNoUndoStep() {
        let a = makeNode(ConstantNode.self)
        let document = model([a])
        #expect(throws: GraphError.self) { try document.perform(.setInput(a.id, "value", .number(.nan))) }
        #expect(!document.canUndo)
    }

    @Test func saveAndReopenPreservesTheDocument() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(3)], output: true)
        let document = model([a])
        document.viewState.dock = .bottom
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.graph == document.graph)
        #expect(reopened.viewState.dock == .bottom)
        await reopened.waitForEvaluation()
        #expect(reopened.results[a.id]?.outputs?["value"]?.numbers == [3])
    }
}
