import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing

struct ListNodeTests {
    /// A Series of `count` numbers 0, 1, 2, … partitioned into rows of `size`: a tree to work on.
    func rows(_ h: inout Harness, count: Int, size: Int) -> Node {
        let series = h.add(SeriesNode.self, ["count": .integer(count)])
        let partition = h.add(PartitionNode.self, ["size": .integer(size)])
        h.wire(series, "values", to: partition, "tree")
        return partition
    }

    // MARK: Partition

    @Test func partitionMakesRowsOutOfAFlatList() async throws {
        var h = Harness()
        let partition = rows(&h, count: 7, size: 3)
        let report = try await h.run([partition])
        #expect(report.value(partition, "tree")?.outline == "[[0,1,2],[3,4,5],[6]]")
        guard case .tree? = report.value(partition, "tree") else { Issue.record("expected a tree"); return }
    }

    @Test func partitionSplitsEveryBranchOfATree() async throws {
        var h = Harness()
        let first = rows(&h, count: 6, size: 3)
        let second = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(first, "tree", to: second, "tree")
        let report = try await h.run([second])
        #expect(report.value(second, "tree")?.outline == "[[[0,1],[2]],[[3,4],[5]]]")
    }

    @Test func partitionRefusesASizeUnderOne() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 0)
        let report = try await h.run([partition])
        #expect(report.error(partition) == "“size” must be at least 1.")
    }

    @Test func partitionOfNothingIsNothing() async throws {
        var h = Harness()
        let partition = rows(&h, count: 0, size: 3)
        let report = try await h.run([partition])
        #expect(report.value(partition, "tree")?.outline == "[]")
    }

    // MARK: Graft

    @Test func graftPutsEachItemInItsOwnBranch() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(3)])
        let graft = h.add(GraftNode.self)
        h.wire(series, "values", to: graft, "tree")
        let report = try await h.run([graft])
        #expect(report.value(graft, "tree")?.outline == "[[0],[1],[2]]")
    }

    @Test func graftGoesOneLevelDeeperOnATree() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let graft = h.add(GraftNode.self)
        h.wire(partition, "tree", to: graft, "tree")
        let report = try await h.run([graft])
        #expect(report.value(graft, "tree")?.outline == "[[[0],[1]],[[2],[3]]]")
        #expect(report.value(graft, "tree")?.depth == 3)
    }

    @Test func graftingASingleValueGivesOneBranchOfOne() async throws {
        var h = Harness()
        let number = h.add(NumberNode.self, ["value": .number(4)])
        let graft = h.add(GraftNode.self)
        h.wire(number, "value", to: graft, "tree")
        let report = try await h.run([graft])
        #expect(report.value(graft, "tree")?.outline == "[[4]]")
    }

    @Test func graftingNothingGivesNothingOneLevelDeeper() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(0)])
        let graft = h.add(GraftNode.self)
        h.wire(series, "values", to: graft, "tree")
        let report = try await h.run([graft])
        #expect(report.value(graft, "tree")?.outline == "[]")
        #expect(report.value(graft, "tree")?.depth == 2)
    }

    // MARK: Flatten

    @Test func flattenWithNoLevelRemovesAllNesting() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 2)
        let flatten = h.add(FlattenNode.self)
        h.wire(partition, "tree", to: flatten, "tree")
        let report = try await h.run([flatten])
        #expect(report.value(flatten, "tree")?.outline == "[0,1,2,3,4,5]")
        guard case .list? = report.value(flatten, "tree") else { Issue.record("expected a flat list"); return }
    }

    @Test func flattenToALevelKeepsTheOuterBranches() async throws {
        var h = Harness()
        let first = rows(&h, count: 8, size: 4)
        let second = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(first, "tree", to: second, "tree")
        let flatten = h.add(FlattenNode.self, ["level": .integer(1)])
        h.wire(second, "tree", to: flatten, "tree")
        let report = try await h.run([flatten])
        #expect(report.value(second, "tree")?.outline == "[[[0,1],[2,3]],[[4,5],[6,7]]]")
        #expect(report.value(flatten, "tree")?.outline == "[[0,1,2,3],[4,5,6,7]]")
    }

    @Test func flattenWithALevelBeyondTheDepthChangesNothing() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let flatten = h.add(FlattenNode.self, ["level": .integer(5)])
        h.wire(partition, "tree", to: flatten, "tree")
        let report = try await h.run([flatten])
        #expect(report.value(flatten, "tree")?.outline == "[[0,1],[2,3]]")
    }

    @Test func flattenRefusesANegativeLevel() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let flatten = h.add(FlattenNode.self, ["level": .integer(-1)])
        h.wire(partition, "tree", to: flatten, "tree")
        let report = try await h.run([flatten])
        #expect(report.error(flatten)?.contains("can't be negative") == true)
    }

    @Test func flattenAcceptsAnythingAndLeavesAFlatListAlone() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self)
        let flatten = h.add(FlattenNode.self)
        h.wire(grid, "points", to: flatten, "tree")
        let report = try await h.run([flatten])
        #expect(report.value(flatten, "tree")?.vectors?.count == 4)
    }

    // MARK: Tree Statistics

    @Test func statisticsDescribeATree() async throws {
        var h = Harness()
        let partition = rows(&h, count: 7, size: 3)
        let stats = h.add(TreeStatisticsNode.self)
        h.wire(partition, "tree", to: stats, "tree")
        let report = try await h.run([stats])
        #expect(report.value(stats, "depth")?.outline == "2")
        #expect(report.value(stats, "branches")?.outline == "3")
        #expect(report.value(stats, "items")?.outline == "7")
        #expect(report.value(stats, "counts")?.outline == "[3,3,1]")
        #expect(report.value(stats, "counts")?.isList == true)
    }

    @Test func statisticsOfNothingIsOneEmptyBranch() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(0)])
        let stats = h.add(TreeStatisticsNode.self)
        h.wire(series, "values", to: stats, "tree")
        let report = try await h.run([stats])
        #expect(report.value(stats, "items")?.outline == "0")
        #expect(report.value(stats, "branches")?.outline == "1")
        #expect(report.value(stats, "counts")?.outline == "[0]")
    }

    @Test func statisticsOfAFlatListIsOneBranchAtDepthOne() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(5)])
        let stats = h.add(TreeStatisticsNode.self)
        h.wire(series, "values", to: stats, "tree")
        let report = try await h.run([stats])
        #expect(report.value(stats, "depth")?.outline == "1")
        #expect(report.value(stats, "branches")?.outline == "1")
        #expect(report.value(stats, "counts")?.outline == "[5]")
    }

    // MARK: through broadcasting

    @Test func aNodeAfterATreeRunsOncePerItemAndKeepsTheTreesShape() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(1), "count": .integer(6)])
        let partition = h.add(PartitionNode.self, ["size": .integer(3)])
        h.wire(series, "values", to: partition, "tree")
        let rectangle = h.add(RectangleNode.self)
        h.wire(partition, "tree", to: rectangle, "width")
        let report = try await h.run([rectangle])
        #expect(report.error(rectangle) == nil)
        #expect(report.value(rectangle, "profile")?.depth == 2)
        #expect(report.value(rectangle, "profile")?.items.count == 6)
    }
}
