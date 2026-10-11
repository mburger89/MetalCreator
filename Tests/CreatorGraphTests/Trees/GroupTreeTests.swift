import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// A tree goes through a group's boundary like any value, and the nodes inside broadcast over it.
struct GroupTreeTests {
    @Test func aTreeCrossesAGroupAndTheNodesInsideBroadcastOverIt() async throws {
        let doubler = Doubler()
        var source = treeRegistry.makeNode(TreeSourceNode.typeID)
        source.inputValues = ["rows": .integer(2), "columns": .integer(2)]
        let group = instance(of: doubler.definition, output: true)
        let wiring = [Link(from: Endpoint(node: source.id, socket: "values"), to: Endpoint(node: group.id, socket: "value"))]
        let graph = Graph(nodes: [source.id: source, group.id: group], links: wiring)
        let evaluator = Evaluator(registry: treeRegistry, kernel: FakeKernel())
        let report = try await evaluator.evaluate(graph, definitions: table([doubler.definition]), demand: [group.id])
        let result = try #require(report.results[group.id])
        #expect(result.state.isSuccess)
        #expect(result.outputs?["result"]?.outline == "[[0,2],[4,6]]")
    }
}
