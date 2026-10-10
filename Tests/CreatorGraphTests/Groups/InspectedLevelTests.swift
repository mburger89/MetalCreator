import CreatorKernel
import Testing
@testable import CreatorGraph

/// The level the graph panel shows is evaluated whole (groups spec §6): every node inside has a state, even one that
/// nothing downstream reads, and such a node never changes the group node's own result.
struct InspectedLevelTests {
    let doubler = Doubler()

    /// "Rib": Group Input's `value` through an Add (both inputs) to Group Output's `result`, and `extra`, which
    /// nothing reads.
    func rib(extra: Node) -> (definition: GroupDefinition, add: Node) {
        let add = makeNode(AddNode.self)
        let definition = define("Rib", inputs: [SocketSpec("value", .number)], outputs: [SocketSpec("result", .number)],
                                nodes: [add, extra]) { input, output in
            [link(input, "value", add, "a"), link(input, "value", add, "b"), link(add, "sum", output, "result")]
        }
        return (definition, add)
    }

    func evaluate(_ g: Graph, _ definitions: [GroupDefinition], demand: [Node], inspecting level: [Node] = []) async throws
        -> EvaluationReport {
        try await Evaluator(registry: testRegistry, kernel: FakeKernel())
            .evaluate(g, definitions: table(definitions), demand: Set(demand.map(\.id)), inspecting: level.map(\.id))
    }

    @Test func aNodeNothingReadsIsEvaluatedOnlyWhileItsLevelIsInspected() async throws {
        let extra = makeNode(ConstantNode.self, ["value": .number(7)])
        let (definition, _) = rib(extra: extra)
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let plain = try await evaluate(graph([group]), [definition], demand: [group])
        #expect(plain.innerResults[[group.id, extra.id]] == nil, "nothing asked for it")
        let shown = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [group])
        #expect(shown.innerResults[[group.id, extra.id]]?.outputs?["value"]?.numbers == [7])
        #expect(shown.results[group.id]?.outputs?["result"]?.numbers == [6], "the group's own result is as before")
    }

    @Test func aGroupNodeNothingDemandsIsEvaluatedToShowItsInside() async throws {
        let (definition, add) = rib(extra: makeNode(ConstantNode.self))
        let group = instance(of: definition, ["value": .number(3)])
        let plain = try await evaluate(graph([group]), [definition], demand: [])
        #expect(plain.results[group.id] == nil && plain.innerResults.isEmpty)
        let shown = try await evaluate(graph([group]), [definition], demand: [], inspecting: [group])
        #expect(shown.innerResults[[group.id, add.id]]?.outputs?["sum"]?.numbers == [6])
    }

    @Test func aFailingNodeNothingFeedsLeavesTheGroupNodeAlone() async throws {
        let failing = makeNode(FailNode.self)
        let (definition, _) = rib(extra: failing)
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let report = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [group])
        #expect(report.innerResults[[group.id, failing.id]]?.state == .error("Boom"))
        #expect(report.results[group.id]?.state.isSuccess == true)
        #expect(report.results[group.id]?.outputs?["result"]?.numbers == [6])
    }

    @Test func aFailingNodeThatFeedsGroupOutputStillFailsTheGroupNode() async throws {
        let failing = makeNode(FailNode.self)
        let definition = define("Broken", outputs: [SocketSpec("result", .number)], nodes: [failing]) { _, output in
            [link(failing, "value", output, "result")]
        }
        let group = instance(of: definition, output: true)
        let report = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [group])
        #expect(report.results[group.id]?.state == .error("Broken › Fail: Boom"))
    }

    @Test func aNestedLevelIsReachedThroughItsGroupNodes() async throws {
        let inner = instance(of: doubler.definition)
        let constant = makeNode(ConstantNode.self, ["value": .number(5)])
        let outer = define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner, constant]) { _, output in
            [link(constant, "value", output, "result")]
        }
        let top = instance(of: outer, output: true)
        let report = try await evaluate(graph([top]), [doubler.definition, outer], demand: [top], inspecting: [top, inner])
        #expect(report.innerResults[[top.id, inner.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [2],
                "inner is wired to nothing in Outer, and is evaluated because its inside is shown")
        #expect(report.results[top.id]?.outputs?["result"]?.numbers == [5])
        let outerOnly = try await evaluate(graph([top]), [doubler.definition, outer], demand: [top], inspecting: [top])
        #expect(outerOnly.innerResults[[top.id, inner.id]]?.state.isSuccess == true, "the nested group node itself")
    }

    @Test func aLevelThatDoesntExistChangesNothing() async throws {
        let (definition, _) = rib(extra: makeNode(ConstantNode.self))
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let plain = try await evaluate(graph([group]), [definition], demand: [group])
        let odd = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [makeNode(AddNode.self)])
        #expect(odd.results[group.id]?.outputs?["result"]?.numbers == plain.results[group.id]?.outputs?["result"]?.numbers)
        #expect(Set(odd.innerResults.keys) == Set(plain.innerResults.keys))
    }

    @MainActor
    @Test func theDocumentEvaluatesTheLevelItsPanelShows() async {
        let extra = makeNode(ConstantNode.self, ["value": .number(7)])
        let (definition, _) = rib(extra: extra)
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([group]), definitions: table([definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        await document.waitForEvaluation()
        #expect(document.innerResults[[group.id, extra.id]] == nil)
        document.inspectedLevel = [group.id]
        await document.waitForEvaluation()
        #expect(document.innerResults[[group.id, extra.id]]?.outputs?["value"]?.numbers == [7])
        document.inspectedLevel = []
        await document.waitForEvaluation()
        #expect(document.innerResults[[group.id, extra.id]] == nil)
    }
}
