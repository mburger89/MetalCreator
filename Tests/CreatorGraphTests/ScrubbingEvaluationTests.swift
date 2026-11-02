import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Reports whether its context was scrubbing; reads the flag, so its cache key holds it.
private enum ScrubProbeNode: NodeDefinition {
    static let typeID = "test.scrubProbe"
    static let displayName = "Scrub Probe"
    static let category = NodeCategory.value
    static let readsScrubbing = true
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("scrubbing", .number)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["scrubbing": .number(context.isScrubbing ? 1 : 0)])
    }
}

private let scrubRegistry = NodeRegistry([ScrubProbeNode.self, ConstantNode.self])

private func probeNode(output: Bool = false) -> Node {
    var node = scrubRegistry.makeNode(ScrubProbeNode.typeID)
    node.isOutput = output
    return node
}

@MainActor
struct ScrubbingEvaluationTests {
    @Test func aNodeThatReadsScrubbingRekeys() async throws {
        let evaluator = Evaluator(registry: scrubRegistry, kernel: FakeKernel())
        let probe = probeNode(), plain = makeNode(ConstantNode.self)
        let g = graph([probe, plain])
        let demand: Set<NodeID> = [probe.id, plain.id]
        var runs: [Set<NodeID>] = []
        for scrubbing in [false, true, false] {
            let report = try await evaluator.evaluate(g, demand: demand, isScrubbing: scrubbing)
            runs.append(Set(report.evaluatedNodes))
            #expect(report.results[probe.id]?.outputs?["scrubbing"]?.numbers == [scrubbing ? 1 : 0])
        }
        #expect(runs[0] == demand)
        #expect(runs[1] == [probe.id], "only the node that reads the flag runs again")
        #expect(runs[2].isEmpty, "the first result is still cached under its own key")
    }

    @Test func endingAScrubSchedulesAnEvaluation() async {
        let probe = probeNode(output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([probe])), registry: scrubRegistry,
                                     kernel: FakeKernel())
        await document.waitForEvaluation()
        #expect(document.results[probe.id]?.outputs?["scrubbing"]?.numbers == [0])
        document.isScrubbing = true
        document.scheduleEvaluation()
        await document.waitForEvaluation()
        #expect(document.results[probe.id]?.outputs?["scrubbing"]?.numbers == [1])
        document.isScrubbing = false
        await document.waitForEvaluation()
        #expect(document.results[probe.id]?.outputs?["scrubbing"]?.numbers == [0])
    }

    @Test func scrubbingIsNotAnEdit() async {
        let probe = probeNode(output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([probe])), registry: scrubRegistry,
                                     kernel: FakeKernel())
        await document.waitForEvaluation()
        let before = document.content
        document.isScrubbing = true
        document.isScrubbing = false
        await document.waitForEvaluation()
        #expect(document.content == before)
        #expect(!document.canUndo)
    }
}
