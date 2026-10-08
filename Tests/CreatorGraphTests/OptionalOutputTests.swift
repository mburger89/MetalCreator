import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct OptionalOutputTests {
    func evaluator() -> Evaluator { Evaluator(registry: testRegistry, kernel: FakeKernel()) }

    @Test func anOptionalOutputMayBeLeftOut() async throws {
        let node = makeNode(OptionalOutputNode.self)
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.state.isSuccess == true)
        #expect(report.results[node.id]?.outputs?["always"]?.numbers == [1])
        #expect(report.results[node.id]?.outputs?["sometimes"] == nil)
    }

    @Test func aProducedOptionalOutputFlows() async throws {
        let node = makeNode(OptionalOutputNode.self, ["flag": .bool(true)])
        let add = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([node, add], [link(node, "sometimes", add, "a")]), demand: [add.id])
        #expect(report.results[add.id]?.outputs?["sum"]?.numbers == [2])
    }

    @Test func wiringAnAbsentOutputExplainsWhy() async throws {
        let node = makeNode(OptionalOutputNode.self)
        let add = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([node, add], [link(node, "sometimes", add, "a")]), demand: [add.id])
        #expect(report.results[add.id]?.state == .error("“a” is wired to “sometimes”, which that node doesn't produce with its current settings."))
    }
}
