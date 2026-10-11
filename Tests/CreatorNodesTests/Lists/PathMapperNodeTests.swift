import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct PathMapperNodeTests {
    /// The integers 0 to `count` − 1 in rows of `size`.
    func rows(_ h: inout Harness, count: Int, size: Int) -> Node {
        let series = h.add(SeriesNode.self, ["count": .integer(count)])
        let partition = h.add(PartitionNode.self, ["size": .integer(size)])
        h.wire(series, "values", to: partition, "tree")
        return partition
    }

    func mapper(_ h: inout Harness, rule: String, after source: Node) -> Node {
        let mapper = h.add(PathMapperNode.self, [NodeSetting.pathRule: .text(rule)])
        h.wire(source, "tree", to: mapper, "tree")
        return mapper
    }

    @Test func aNewNodeCarriesARuleThatChangesNothing() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let mapper = h.add(PathMapperNode.self)
        h.wire(partition, "tree", to: mapper, "tree")
        #expect(BuiltInNodes.registry.makeNode(PathMapperNode.typeID).inputValues[NodeSetting.pathRule] == .text("{A} → {A}"))
        let report = try await h.run([mapper])
        #expect(report.value(mapper, "tree")?.outline == "[[0,1,2],[3,4,5]]")
        #expect(report.isOK(mapper))
    }

    @Test func transposingATable() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let mapper = mapper(&h, rule: "{A} → {(i)}", after: partition)
        let report = try await h.run([mapper])
        #expect(report.value(mapper, "tree")?.outline == "[[0,3],[1,4],[2,5]]")
        #expect(report.value(mapper, "tree")?.depth == 2)
    }

    @Test func ruleAndDepthChangesFlowOnToTheNextNode() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let mapper = mapper(&h, rule: "{A} → {A;(i)}", after: partition)
        let stats = h.add(TreeStatisticsNode.self)
        h.wire(mapper, "tree", to: stats, "tree")
        let report = try await h.run([stats])
        #expect(report.value(stats, "depth")?.outline == "3")
        #expect(report.value(stats, "branches")?.outline == "4")
    }

    @Test func aRuleMatchingSomeBranchesWarnsAndKeepsTheRest() async throws {
        var h = Harness()
        let first = rows(&h, count: 12, size: 6)
        let second = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(first, "tree", to: second, "tree")
        let mapper = mapper(&h, rule: "{A;A} → {A;A}", after: second)
        let report = try await h.run([mapper])
        #expect(report.warning(mapper) == "The rule matched 2 of 6 branches; the other 4 stay where they were.")
        #expect(report.value(mapper, "tree")?.outline == report.value(second, "tree")?.outline)
    }

    @Test func anItemRuleWarnsInItemsNotBranches() async throws {
        var h = Harness()
        let source = rows(&h, count: 12, size: 4)
        let mapper = mapper(&h, rule: "{A;A} → {0}", after: source)
        let report = try await h.run([mapper])
        #expect(report.warning(mapper) == "The rule matched 3 of 12 items; the other 9 stay in their own branch. "
                + "1 of them shares a branch with the results, so their items are mixed in.")
    }

    @Test func aLeftBranchThatSharesAPathWithAResultSaysSo() async throws {
        var h = Harness()
        let first = rows(&h, count: 12, size: 6)
        let second = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(first, "tree", to: second, "tree")
        let mapper = mapper(&h, rule: "{0;B} → {B;0}", after: second)
        let report = try await h.run([mapper])
        #expect(report.warning(mapper) == "The rule matched 3 of 6 branches; the other 3 stay where they were. "
                + "1 of them shares a branch with the results, so their items are mixed in.")
    }

    @Test func aRuleThatDoesNotReadRefusesWithTheFailingPart() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let mapper = mapper(&h, rule: "{A} → {B}", after: partition)
        let report = try await h.run([mapper])
        #expect(report.error(mapper) == "The target uses “B”, but the source {A} only names A.")
    }

    @Test func aSourceOfTheWrongDepthRefusesNamingBothShapes() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let mapper = mapper(&h, rule: "{A;B;C} → {A}", after: partition)
        let report = try await h.run([mapper])
        #expect(report.error(mapper) == "The rule's source {A;B;C} names 3 levels, but this tree (2 × 3) has 1 level of branches. "
                + "Write the source with 1 level, like {A}, or with 2, like {A;B}, to name items too.")
    }

    @Test func aSourceThatNamesItemsTransposesAGrid() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let mapper = mapper(&h, rule: "{A;B} → {B;A}", after: partition)
        let report = try await h.run([mapper])
        #expect(report.value(mapper, "tree")?.outline == "[[0,3],[1,4],[2,5]]")
        #expect(report.isOK(mapper))
    }

    @Test func aMissingRuleSettingIsAnEmptyRule() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let mapper = h.add(PathMapperNode.self)
        h.set(mapper, NodeSetting.pathRule, nil)
        h.wire(partition, "tree", to: mapper, "tree")
        let report = try await h.run([mapper])
        #expect(report.error(mapper) == "The rule is empty. Write it like {A;B} → {B;A}.")
    }

    @Test func theRuleIsPartOfTheNodesCacheKey() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let mapper = mapper(&h, rule: "{A} → {A}", after: partition)
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let first = try await evaluator.evaluate(h.graph, demand: [mapper.id])
        h.set(mapper, NodeSetting.pathRule, .text("{A} → {(i)}"))
        let second = try await evaluator.evaluate(h.graph, demand: [mapper.id])
        #expect(first.results[mapper.id]?.outputs?["tree"]?.outline == "[[0,1],[2,3]]")
        #expect(second.results[mapper.id]?.outputs?["tree"]?.outline == "[[0,2],[1,3]]")
    }
}
