import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Returns one fact per iteration, so a test sees whose facts a result keeps.
private enum FactsProbeNode: NodeDefinition {
    static let typeID = "test.factsProbe"
    static let displayName = "Facts Probe"
    static let category = NodeCategory.value
    static let factsTitle = "Board"
    static let inputs = [SocketSpec("n", .number)]
    static let outputs = [SocketSpec("out", .number)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let value = try inputs.number("n")
        var outputs = NodeOutputs(["out": .number(value)])
        outputs.facts = [PayloadFact("Value", "\(Int(value))")]
        return outputs
    }
}

@MainActor
struct NodeFactsTests {
    @Test func theDefaultFactsTitleIsFacts() {
        #expect(ConstantNode.factsTitle == "Facts")
        #expect(FactsProbeNode.factsTitle == "Board")
    }

    @Test func aResultKeepsFactsThroughTheCache() async throws {
        let registry = NodeRegistry([FactsProbeNode.self, ConstantNode.self, ListSourceNode.self])
        var probe = registry.makeNode(FactsProbeNode.typeID)
        probe.inputValues["n"] = .number(7)
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let g = graph([probe])
        let first = try await evaluator.evaluate(g, demand: [probe.id])
        #expect(first.results[probe.id]?.facts == [PayloadFact("Value", "7")])
        let second = try await evaluator.evaluate(g, demand: [probe.id])
        #expect(second.evaluatedNodes.isEmpty, "served from the cache")
        #expect(second.results[probe.id]?.facts == [PayloadFact("Value", "7")])
    }

    @Test func aBroadcastNodeKeepsTheFirstIterationsFacts() async throws {
        let registry = NodeRegistry([FactsProbeNode.self, ConstantNode.self, ListSourceNode.self])
        let source = makeNode(ListSourceNode.self)
        let probe = registry.makeNode(FactsProbeNode.typeID)
        let link = Link(from: Endpoint(node: source.id, socket: "values"), to: Endpoint(node: probe.id, socket: "n"))
        let evaluator = Evaluator(registry: registry, kernel: FakeKernel())
        let report = try await evaluator.evaluate(graph([source, probe], [link]), demand: [probe.id])
        #expect(report.results[probe.id]?.facts == [PayloadFact("Value", "0")])
    }
}
