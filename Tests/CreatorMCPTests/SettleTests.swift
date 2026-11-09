import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorMCP

@MainActor struct SettleTests {
    /// An evaluation that does not finish: `settle` gives up at its limit instead of waiting for it.
    @Test func settleReturnsFalseWhenTheEvaluationOutlastsTheLimit() async throws {
        let registry = NodeRegistry(BuiltInNodes.all + [StallNode.self])
        let document = DocumentModel(registry: registry, kernel: FakeKernel())
        let session = DocumentModelSession(document: document)
        await StallNode.gate.close()
        var node = registry.makeNode(StallNode.typeID)
        node.isOutput = true
        try document.perform(.addNode(node), name: "Add Node")
        let start = ContinuousClock.now
        let settled = await session.settle(within: .milliseconds(200))
        #expect(!settled)
        #expect(ContinuousClock.now - start < .seconds(5), "it returned promptly")
        await StallNode.gate.open()
        await document.waitForEvaluation()
        #expect(await session.settle(within: .seconds(60)))
    }
}
