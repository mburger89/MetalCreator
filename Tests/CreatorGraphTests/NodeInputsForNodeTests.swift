import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// `NodeDefinition.inputs(for:)` (S4): sockets that depend on a node's settings, like the Sketch
/// node's exposed dimensions, are wired, gathered, broadcast and cached like declared ones.
struct NodeInputsForNodeTests {
    func evaluator() -> Evaluator { Evaluator(registry: testRegistry, kernel: FakeKernel()) }

    @Test func aDeclaredTypeHasItsFixedInputs() {
        #expect(AddNode.inputs(for: makeNode(AddNode.self)) == AddNode.inputs)
    }

    @Test func anExtraSocketCanBeWiredAndIsGathered() async throws {
        let five = makeNode(ConstantNode.self, ["value": .number(5)])
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        let wired = graph([five, node], [link(five, "value", node, "k")])
        #expect(wired.connectionProblem(from: Endpoint(node: five.id, socket: "value"),
                                        to: Endpoint(node: node.id, socket: "k"), registry: testRegistry) == nil)
        let report = try await evaluator().evaluate(wired, demand: [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [5])
    }

    @Test func anUnwiredExtraSocketUsesItsDefault() async throws {
        let node = makeNode(ExtraInputsNode.self, ["value": .number(2), "extra": .text("k,m")])
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [4])
    }

    @Test func aSocketTheNodeDoesNotListIsRefused() {
        let five = makeNode(ConstantNode.self)
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        #expect(graph([five, node]).connectionProblem(from: Endpoint(node: five.id, socket: "value"),
                                                     to: Endpoint(node: node.id, socket: "q"),
                                                     registry: testRegistry) == .unknownSocket("q"))
    }

    @Test func anExtraSocketBroadcasts() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        let report = try await evaluator().evaluate(graph([list, node], [link(list, "values", node, "k")]), demand: [node.id])
        let sum = try #require(report.results[node.id]?.outputs?["sum"])
        #expect(sum.isList)
        #expect(sum.numbers == [0, 1, 2])
    }

    @Test func aWireToASocketTheNodeNoLongerListsIsIgnored() async throws {
        let five = makeNode(ConstantNode.self, ["value": .number(5)])
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("")])
        let report = try await evaluator().evaluate(graph([five, node], [link(five, "value", node, "k")]), demand: [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [0])
    }

    @Test func changingTheExtraSocketsInvalidatesTheCache() async throws {
        let evaluator = evaluator()
        var node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        _ = try await evaluator.evaluate(graph([node]), demand: [node.id])
        node.inputValues["extra"] = .text("k,m")
        let report = try await evaluator.evaluate(graph([node]), demand: [node.id])
        #expect(report.evaluatedNodes == [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [2])
    }
}
