import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorMCP

@MainActor @Suite(.timeLimit(.minutes(5))) struct SettleTests {
    /// An evaluation that does not finish: `settle` gives up at its limit instead of waiting for it. The node stays stalled
    /// until `settle` has returned, so a `settle` that waited for the evaluation would never return (the time limit fails
    /// it); no wall-clock bound is needed, and none is asserted, since a loaded machine can stretch the 200 ms limit.
    @Test func settleReturnsFalseWhenTheEvaluationOutlastsTheLimit() async throws {
        let registry = NodeRegistry(BuiltInNodes.all + [StallNode.self])
        let document = DocumentModel(registry: registry, kernel: FakeKernel())
        let session = DocumentModelSession(document: document)
        await StallNode.gate.close()
        var node = registry.makeNode(StallNode.typeID)
        node.isOutput = true
        try document.perform(.addNode(node), name: "Add Node")
        let settled = await session.settle(within: .milliseconds(200))
        #expect(!settled)
        await StallNode.gate.open()
        await document.waitForEvaluation()
        #expect(await session.settle(within: .seconds(60)))
    }
}
