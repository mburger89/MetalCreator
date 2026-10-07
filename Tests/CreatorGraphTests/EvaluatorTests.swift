import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct EvaluatorTests {
    func evaluator() -> Evaluator { Evaluator(registry: testRegistry, kernel: FakeKernel()) }

    @Test func wiredValuesFlowDownstream() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(2)])
        let b = makeNode(AddNode.self, ["b": .number(3)], output: true)
        let report = try await evaluator().evaluate(graph([a, b], [link(a, "value", b, "a")]), demand: [b.id])
        #expect(report.results[b.id]?.outputs?["sum"]?.numbers == [5])
        #expect(report.results[b.id]?.state.isSuccess == true)
    }

    @Test func integerWireIsWidenedToNumber() async throws {
        let a = makeNode(IntegerNode.self, ["value": .integer(4)])
        let b = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([a, b], [link(a, "value", b, "a")]), demand: [b.id])
        #expect(report.results[b.id]?.outputs?["sum"]?.numbers == [4])
    }

    @Test func listsBroadcastThroughDownstreamNodes() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let add = makeNode(AddNode.self, ["b": .number(10)])
        let report = try await evaluator().evaluate(graph([list, add], [link(list, "values", add, "a")]), demand: [add.id])
        let sum = try #require(report.results[add.id]?.outputs?["sum"])
        #expect(sum.isList)
        #expect(sum.numbers == [10, 11, 12])
    }

    @Test func listAccessNodeSumsAWiredList() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(2)])
        let sum = makeNode(SumListNode.self)
        let report = try await evaluator().evaluate(graph([a, sum], [link(a, "value", sum, "values")]), demand: [sum.id])
        #expect(report.results[sum.id]?.outputs?["sum"]?.numbers == [2])
    }

    @Test func failingNodeShowsErrorAndDownstreamWaits() async throws {
        let fail = makeNode(FailNode.self)
        let add = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([fail, add], [link(fail, "value", add, "a")]), demand: [add.id])
        #expect(report.results[fail.id]?.state == .error("Boom"))
        guard case .idle(let reason?)? = report.results[add.id]?.state else { Issue.record("expected idle"); return }
        #expect(reason.contains("“a”"))
    }

    @Test func requiredUnwiredInputBlocksWithAPrompt() async throws {
        let node = makeNode(RequiredNode.self)
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.state == .idle("Connect or set “value”."))
    }

    @Test func warningsSurfaceAsWarningState() async throws {
        let node = makeNode(WarnNode.self, ["value": .number(1)])
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.state == .warning("Careful"))
        #expect(report.results[node.id]?.outputs?["value"]?.numbers == [1])
    }

    @Test func kernelErrorsBecomePlainLanguage() async throws {
        let box = makeNode(BoxNode.self, ["distance": .number(-5)])
        let report = try await evaluator().evaluate(graph([box]), demand: [box.id])
        #expect(report.results[box.id]?.state == .error("Extrude distance must be greater than 0 mm."))
    }

    @Test func parametersFeedParameterNodes() async throws {
        let parameter = GraphParameter(name: "Width", type: .number, value: .number(60))
        let node = makeNode(ParameterNode.self, ["parameter": .text(parameter.id.rawValue.uuidString)])
        let report = try await evaluator().evaluate(graph([node], parameters: [parameter]), demand: [node.id])
        #expect(report.results[node.id]?.outputs?["value"]?.numbers == [60])
    }

    @Test func unknownNodeTypeIsAnErrorNotACrash() async throws {
        var node = makeNode(ConstantNode.self)
        node.typeID = "future.node"
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        guard case .error(let message)? = report.results[node.id]?.state else { Issue.record("expected error"); return }
        #expect(message.contains("future.node"))
    }

    @Test func cycleInFileIsReportedNotFatal() async throws {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([a, b], [link(a, "sum", b, "a"), link(b, "sum", a, "a")]), demand: [b.id])
        guard case .error(let message)? = report.results[a.id]?.state else { Issue.record("expected error"); return }
        #expect(message.contains("cycle"))
    }

    @Test func danglingLinkBlocksNode() async throws {
        let ghost = makeNode(ConstantNode.self)
        let add = makeNode(AddNode.self)
        // `ghost` is wired in but missing from the graph, as in a corrupt file.
        let report = try await evaluator().evaluate(graph([add], [link(ghost, "value", add, "a")]), demand: [add.id])
        guard case .idle? = report.results[add.id]?.state else { Issue.record("expected idle"); return }
    }

    @Test func emptyBroadcastGivesEmptyListNotError() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(0)])
        let add = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([list, add], [link(list, "values", add, "a")]), demand: [add.id])
        #expect(report.results[add.id]?.state.isSuccess == true)
        #expect(report.results[add.id]?.outputs?["sum"]?.numbers == [])
    }

    @Test func generatorOutputsAreListsEvenWhenSingle() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(1)])
        let report = try await evaluator().evaluate(graph([list]), demand: [list.id])
        #expect(report.results[list.id]?.outputs?["values"]?.isList == true)
    }

    @Test func identicalNodesDoNotShareCachedTags() async throws {
        let first = makeNode(BoxNode.self), second = makeNode(BoxNode.self)
        let report = try await evaluator().evaluate(graph([first, second]), demand: [first.id, second.id])
        #expect(Set(report.evaluatedNodes) == [first.id, second.id])
        for id in [first.id, second.id] {
            guard case .solid(let solid)? = report.results[id]?.outputs?["solid"]?.items.first else {
                Issue.record("expected a solid"); return
            }
            let tags = solid.topology.faces.flatMap(\.tags)
            #expect(!tags.isEmpty)
            #expect(tags.allSatisfy { $0.node == id })
        }
    }
}
