import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct CacheTests {
    @Test func unchangedGraphIsFullyCached() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)]), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "value", b, "a")])
        _ = try await evaluator.evaluate(g, demand: [b.id])
        let second = try await evaluator.evaluate(g, demand: [b.id])
        #expect(second.evaluatedNodes.isEmpty)
        #expect(second.results[b.id]?.outputs?["sum"]?.numbers == [1])
    }

    @Test func editingDownstreamKeepsUpstreamCached() async throws {
        let kernel = FakeKernel()
        let evaluator = Evaluator(registry: testRegistry, kernel: kernel)
        let box = makeNode(BoxNode.self)
        let add = makeNode(AddNode.self, ["b": .number(1)])
        var g = graph([box, add])
        _ = try await evaluator.evaluate(g, demand: [box.id, add.id])
        g.nodes[add.id]?.inputValues["b"] = .number(2)
        let second = try await evaluator.evaluate(g, demand: [box.id, add.id])
        #expect(second.evaluatedNodes == [add.id])
        #expect(await kernel.operationLog == ["extrude"])
    }

    @Test func editingUpstreamInvalidatesDownstream() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)]), b = makeNode(AddNode.self)
        var g = graph([a, b], [link(a, "value", b, "a")])
        _ = try await evaluator.evaluate(g, demand: [b.id])
        g.nodes[a.id]?.inputValues["value"] = .number(5)
        let second = try await evaluator.evaluate(g, demand: [b.id])
        #expect(Set(second.evaluatedNodes) == [a.id, b.id])
        #expect(second.results[b.id]?.outputs?["sum"]?.numbers == [5])
    }

    @Test func undoToAPreviousValueHitsTheCache() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)])
        var g = graph([a])
        _ = try await evaluator.evaluate(g, demand: [a.id])
        g.nodes[a.id]?.inputValues["value"] = .number(2)
        _ = try await evaluator.evaluate(g, demand: [a.id])
        g.nodes[a.id]?.inputValues["value"] = .number(1)
        #expect(try await evaluator.evaluate(g, demand: [a.id]).evaluatedNodes.isEmpty)
    }

    @Test func parameterEditsInvalidateParameterReaders() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        var parameter = GraphParameter(name: "Width", type: .number, value: .number(60))
        let node = makeNode(ParameterNode.self, ["parameter": .text(parameter.id.rawValue.uuidString)])
        _ = try await evaluator.evaluate(graph([node], parameters: [parameter]), demand: [node.id])
        parameter.value = .number(90)
        let second = try await evaluator.evaluate(graph([node], parameters: [parameter]), demand: [node.id])
        #expect(second.results[node.id]?.outputs?["value"]?.numbers == [90])
    }

    @Test func errorsAreNotCached() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let fail = makeNode(FailNode.self)
        _ = try await evaluator.evaluate(graph([fail]), demand: [fail.id])
        #expect(try await evaluator.evaluate(graph([fail]), demand: [fail.id]).evaluatedNodes == [fail.id])
    }

    @Test func deletedNodesLeaveTheCache() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self), b = makeNode(ConstantNode.self, ["value": .number(2)])
        _ = try await evaluator.evaluate(graph([a, b]), demand: [a.id, b.id])
        #expect(await evaluator.cachedEntryCount == 2)
        _ = try await evaluator.evaluate(graph([a]), demand: [a.id])
        #expect(await evaluator.cachedEntryCount == 1)
    }

    @Test func tinyBudgetEvictsLeastRecentlyUsed() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel(), cacheBudgetBytes: 300)
        let nodes = (0..<5).map { makeNode(ConstantNode.self, ["value": .number(Double($0))]) }
        _ = try await evaluator.evaluate(graph(nodes), demand: Set(nodes.map(\.id)))
        #expect(await evaluator.cachedEntryCount < 5)
    }

    @Test func cancellingStopsBetweenNodes() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let slow = makeNode(SlowNode.self), after = makeNode(AddNode.self)
        let g = graph([slow, after], [link(slow, "value", after, "a")])
        let task = Task { try await evaluator.evaluate(g, demand: [after.id]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
