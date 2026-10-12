import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Cull Pattern (patterns spec §4): a true/false mask repeated across each branch, and a cull keeps paths.
struct CullPatternNodeTests {
    func run(_ pattern: String, count: Int = 6, rows: Int? = nil,
             overall: Bool = false) async throws -> (report: EvaluationReport, cull: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(pattern), "scope": .integer(overall ? 1 : 0)])
        h.wire(source, to: cull, "tree")
        return (try await h.run([cull]), cull)
    }

    @Test func everyOtherItemOfAFlatListSurvivesAtItsOwnIndex() async throws {
        let (report, cull) = try await run("1 0")
        #expect(report.value(cull, "tree")?.outline == "[0,2,4]")
        #expect(report.positions(cull) == [[0, 2, 4]])
        #expect(report.tree(cull)?.isCulled == true)
    }

    @Test func theMaskStartsAgainAtEveryBranch() async throws {
        let (report, cull) = try await run("1 1 0", count: 8, rows: 4)
        #expect(report.value(cull, "tree")?.outline == "[[0,1,3],[4,5,7]]")
        #expect(report.positions(cull) == [[0, 1, 3], [0, 1, 3]])
    }

    @Test func aMaskLongerThanTheBranchJustStopsEarly() async throws {
        let (report, cull) = try await run("0 1 1 1 1 1", count: 6, rows: 2)
        #expect(report.positions(cull) == [[1], [1], [1]])
    }

    @Test func overallTheMaskRunsOnFromBranchToBranch() async throws {
        let (report, cull) = try await run("1 0 0", count: 8, rows: 4, overall: true)
        #expect(report.positions(cull) == [[0, 3], [2]], "items 0, 3 and 6 of the tree: {0;0}, {0;3} and {1;2}")
        let (flat, flatCull) = try await run("1 0", count: 6, overall: true)
        #expect(flat.positions(flatCull) == [[0, 2, 4]], "on a flat list both scopes say the same")
    }

    @Test func overallCountsTheItemsLeftByAnEarlierCull() async throws {
        var h = Harness()
        let source = h.source(count: 6, rows: 2)
        let first = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])  // keeps {0;0}, {1;0}, {2;0}
        let second = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0"), "scope": .integer(1)])
        h.wire(source, to: first, "tree")
        h.wire(first, "tree", to: second, "tree")
        let report = try await h.run([second])
        #expect(report.positions(second) == [[0], [], [0]], "the three survivors are counted 1 0 1; the middle one goes")
    }

    @Test func aSecondCullCountsTheSurvivorsAndKeepsTheFirstOnesIndices() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let first = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let second = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        h.wire(source, to: first, "tree")
        h.wire(first, "tree", to: second, "tree")
        let report = try await h.run([second])
        #expect(report.value(second, "tree")?.outline == "[0,4]")
        #expect(report.positions(second) == [[0, 4]], "{0} and {4}: the survivors of {0, 2, 4}, not renumbered")
    }

    @Test func aReshapingNodeAfterACullRenumbersAsReshapingDoes() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let rows = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(source, to: cull, "tree")
        h.wire(cull, "tree", to: rows, "tree")
        let report = try await h.run([rows])
        #expect(report.value(rows, "tree")?.outline == "[[0,2],[4]]")
        #expect(report.positions(rows) == [[0, 1], [0]], "Partition makes new branches, so the items are counted afresh")
    }

    @Test func aMaskThatKeepsEverythingChangesNothingAndSaysNothing() async throws {
        let (report, cull) = try await run("1")
        #expect(report.isOK(cull))
        #expect(report.value(cull, "tree")?.isList == true, "a plain list stays a plain list")
    }

    @Test func aMaskThatCullsEverythingLeavesEmptyBranches() async throws {
        let (report, cull) = try await run("0", count: 4, rows: 2)
        #expect(report.value(cull, "tree")?.outline == "[[],[]]")
        #expect(report.positions(cull) == [[], []])
    }

    @Test func tAndFAndCommasAreAccepted() async throws {
        let (report, cull) = try await run("T,f,t", count: 6)
        #expect(report.positions(cull) == [[0, 2, 3, 5]])
    }

    @Test func aScopeThatIsNeitherIsRefused() async throws {
        var h = Harness()
        let source = h.source(count: 4)
        let cull = h.add(CullPatternNode.self, ["scope": .integer(5)])
        h.wire(source, to: cull, "tree")
        let report = try await h.run([cull])
        #expect(report.error(cull) == "Choose Per branch or Overall for “scope”.")
    }

    @Test func aBadPatternNamesItself() async throws {
        let (report, cull) = try await run("1 2 0")
        #expect(report.error(cull) == "“1 2 0” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1.")
        let (blank, blankCull) = try await run("  ")
        #expect(blank.error(blankCull) == "The pattern is empty. Write 1 to keep an item and 0 to cull it, like 1 0 1.")
    }

    /// Runs the node by hand, with `inputs` as the evaluator would hand them over.
    func evaluate(_ inputs: NodeInputs) async throws -> NodeOutputs {
        let node = BuiltInNodes.registry.makeNode(CullPatternNode.typeID)
        return try await CullPatternNode.evaluate(inputs, kernel: FakeKernel(), context: EvalContext(node: node, item: 0, parameters: [:]))
    }

    @Test func aWiredListOfBooleansTakesThePlaceOfTheText() async throws {
        let tree = DataTree.list((0..<4).map { .integer($0) })
        let slots: [SocketName: NodeInputs.Slot] = [
            "tree": .tree(tree), "keep": .list([.bool(false), .bool(true)]), "scope": .item(.integer(0)),
        ]
        let outputs = try await evaluate(NodeInputs(item: 0, slots: slots))
        #expect(try #require(outputs.trees["tree"]).itemPositions == [1, 3])
    }

    @Test func anEmptyWiredListIsRefused() async throws {
        let inputs = NodeInputs(item: 0, slots: ["tree": .tree(.list([.integer(1)])), "keep": .list([]), "scope": .item(.integer(0))])
        await #expect(throws: NodeError.self) { _ = try await evaluate(inputs) }
    }

    @Test func itCullsAnyKindOfItem() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1)])
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("0 1 1")])
        h.wire(grid, "points", to: cull, "tree")
        let report = try await h.run([cull])
        #expect(report.value(cull, "tree")?.vectors?.count == 2)
        #expect(report.positions(cull) == [[1, 2]])
    }

    @Test func theNodeStartsWithAPatternThatKeepsEveryOtherItem() {
        let node = BuiltInNodes.registry.makeNode(CullPatternNode.typeID)
        #expect(node.inputValues[NodeSetting.cullPattern] == .text("1 0"))
        #expect(CullPatternNode.inputs.first { $0.name == "scope" }?.defaultValue == .integer(0), "per branch, as for rows")
        #expect(CullPatternNode.category == .patterns)
    }
}
