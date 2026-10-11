import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct EvaluatorTreeTests {
    func evaluator() -> Evaluator { Evaluator(registry: treeRegistry, kernel: FakeKernel()) }

    func run(_ nodes: [Node], _ links: [Link] = [], demand: Node) async throws -> NodeResult {
        let report = try await evaluator().evaluate(treeGraph(nodes, links), demand: [demand.id])
        return try #require(report.results[demand.id])
    }

    func treeGraph(_ nodes: [Node], _ links: [Link]) -> Graph {
        Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links)
    }

    func node(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        var made = treeRegistry.makeNode(definition.typeID)
        made.inputValues = values
        return made
    }

    @Test func aNodeWithNoInputsCanMakeATree() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(2), "columns": .integer(3)])
        let result = try await run([source], demand: source)
        #expect(result.outputs?["values"]?.outline == "[[0,1,2],[3,4,5]]")
        guard case .tree? = result.outputs?["values"] else { Issue.record("expected a tree"); return }
    }

    @Test func aTreeBroadcastsThroughAnItemNodeAndKeepsItsShape() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(2), "columns": .integer(2)])
        let add = node(AddNode.self, ["b": .number(10)])
        let result = try await run([source, add], [link(source, "values", add, "a")], demand: add)
        #expect(result.outputs?["sum"]?.outline == "[[10,11],[12,13]]")
        #expect(result.state.isSuccess)
    }

    @Test func aFlatListAppliesToEveryBranch() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(2), "columns": .integer(3)])
        let list = node(ListSourceNode.self, ["count": .integer(3)])
        let add = node(AddNode.self)
        let result = try await run([source, list, add],
                                   [link(source, "values", add, "a"), link(list, "values", add, "b")], demand: add)
        #expect(result.outputs?["sum"]?.outline == "[[0,2,4],[3,5,7]]")
    }

    @Test func aListSocketGetsOneBranchPerRun() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(3), "columns": .integer(4)])
        let sum = node(SumListNode.self)
        let result = try await run([source, sum], [link(source, "values", sum, "values")], demand: sum)
        #expect(result.outputs?["sum"]?.outline == "[6,22,38]")
        guard case .list? = result.outputs?["sum"] else { Issue.record("expected a list"); return }
    }

    @Test func aTreeSocketGetsTheWholeTree() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(3), "columns": .integer(4)])
        let depth = node(TreeDepthNode.self)
        let result = try await run([source, depth], [link(source, "values", depth, "tree")], demand: depth)
        #expect(result.outputs?["depth"]?.outline == "2")
        #expect(result.outputs?["count"]?.outline == "12")
    }

    @Test func aTreeSocketAlsoTakesAFlatListAndASingleItem() async throws {
        let list = node(ListSourceNode.self, ["count": .integer(4)])
        let depth = node(TreeDepthNode.self)
        let flat = try await run([list, depth], [link(list, "values", depth, "tree")], demand: depth)
        #expect(flat.outputs?["depth"]?.outline == "1")
        #expect(flat.outputs?["count"]?.outline == "4")
        let constant = node(ConstantNode.self, ["value": .number(7)])
        let lone = node(TreeDepthNode.self)
        let single = try await run([constant, lone], [link(constant, "value", lone, "tree")], demand: lone)
        #expect(single.outputs?["count"]?.outline == "1")
    }

    @Test func aNodeReturningATreeGivesItAsTheOutput() async throws {
        let list = node(ListSourceNode.self, ["count": .integer(3)])
        let graft = node(TreeGraftNode.self)
        let result = try await run([list, graft], [link(list, "values", graft, "tree")], demand: graft)
        #expect(result.outputs?["tree"]?.outline == "[[0],[1],[2]]")
    }

    @Test func aTreeNodeFollowedByAnItemNodeBroadcastsOverTheTree() async throws {
        let list = node(ListSourceNode.self, ["count": .integer(3)])
        let graft = node(TreeGraftNode.self)
        let add = node(AddNode.self, ["b": .number(0.5)])
        let result = try await run([list, graft, add],
                                   [link(list, "values", graft, "tree"), link(graft, "tree", add, "a")], demand: add)
        #expect(result.outputs?["sum"]?.outline == "[[0.5],[1.5],[2.5]]")
    }

    @Test func aTreeNodeWithAListOnAnItemInputIsRefusedInPlainWords() async throws {
        let list = node(ListSourceNode.self, ["count": .integer(3)])
        let times = node(IntListNode.self, ["count": .integer(2)])
        let graft = node(TreeGraftNode.self)
        let result = try await run([list, times, graft],
                                   [link(list, "values", graft, "tree"), link(times, "values", graft, "times")], demand: graft)
        guard case .error(let message) = result.state else { Issue.record("expected an error"); return }
        #expect(message == "This node works on a whole tree at once, so its other inputs must be single values, not lists.")
    }

    @Test func treesOfTheSameDepthDoNotWarn() async throws {
        let wide = node(TreeSourceNode.self, ["rows": .integer(2), "columns": .integer(2)])
        let list = node(ListSourceNode.self, ["count": .integer(2)])
        let graft = node(TreeGraftNode.self)
        let add = node(AddNode.self)
        let result = try await run([wide, list, graft, add],
                                   [link(wide, "values", add, "a"), link(list, "values", graft, "tree"),
                                    link(graft, "tree", add, "b"),
                                   ], demand: add)
        guard case .ok = result.state else { Issue.record("expected ok, got \(result.state)"); return }
        #expect(result.outputs?["sum"]?.outline == "[[0,1],[3,4]]")
    }

    @Test func differentDepthsWarnWithBothShapes() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(2), "columns": .integer(2)])
        let list = node(ListSourceNode.self, ["count": .integer(2)])
        let graft = node(TreeGraftNode.self, ["times": .integer(2)])
        let add = node(AddNode.self)
        let result = try await run([source, list, graft, add],
                                   [link(source, "values", add, "a"), link(list, "values", graft, "tree"),
                                    link(graft, "tree", add, "b"),
                                   ], demand: add)
        guard case .warning(let message) = result.state else { Issue.record("expected a warning, got \(result.state)"); return }
        #expect(message.contains("“a” (2 × 2)"))
        #expect(message.contains("“b” (2 × 1 × 1)"))
        #expect(result.outputs?["sum"]?.depth == 3)
    }

    @Test func lopsidedTreesFailWithTheLimitMessage() async throws {
        let tall = node(TreeSourceNode.self, ["rows": .integer(1000), "columns": .integer(1)])
        let wide = node(TreeSourceNode.self, ["rows": .integer(1), "columns": .integer(1000)])
        let add = node(AddNode.self)
        let result = try await run([tall, wide, add],
                                   [link(tall, "values", add, "a"), link(wide, "values", add, "b")], demand: add)
        guard case .error(let message) = result.state else { Issue.record("expected an error"); return }
        #expect(message.contains("100,000"))
    }

    @Test func anEmptyTreeGivesAnEmptyTreeOfTheSameDepth() async throws {
        let source = node(TreeSourceNode.self, ["rows": .integer(0)])
        let add = node(AddNode.self, ["b": .number(1)])
        let result = try await run([source, add], [link(source, "values", add, "a")], demand: add)
        #expect(result.state.isSuccess)
        #expect(result.outputs?["sum"]?.outline == "[]")
        #expect(result.outputs?["sum"]?.depth == 2)
    }

    @Test func flatGraphsGiveTheSameValuesAsBefore() async throws {
        let list = node(ListSourceNode.self, ["count": .integer(3)])
        let add = node(AddNode.self, ["b": .number(10)])
        let result = try await run([list, add], [link(list, "values", add, "a")], demand: add)
        guard case .list? = result.outputs?["sum"] else { Issue.record("expected a list"); return }
        #expect(result.outputs?["sum"]?.numbers == [10, 11, 12])
        let lone = node(AddNode.self, ["a": .number(1), "b": .number(2)])
        let single = try await run([lone], demand: lone)
        guard case .one? = single.outputs?["sum"] else { Issue.record("expected one"); return }
    }
}
