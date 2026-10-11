import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing

struct ItemAndBranchNodeTests {
    /// 0, 1, 2, … of `count` numbers in rows of `size`.
    func rows(_ h: inout Harness, count: Int, size: Int) -> Node {
        let series = h.add(SeriesNode.self, ["count": .integer(count)])
        let partition = h.add(PartitionNode.self, ["size": .integer(size)])
        h.wire(series, "values", to: partition, "tree")
        return partition
    }

    // MARK: List Item

    @Test func listItemTakesTheSameIndexFromEveryBranch() async throws {
        var h = Harness()
        let partition = rows(&h, count: 9, size: 3)
        let item = h.add(ListItemNode.self, ["index": .integer(1)])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[[1],[4],[7]]")
        #expect(report.isOK(item))
    }

    @Test func listItemOnAFlatListGivesThatOneItem() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(10), "count": .integer(4)])
        let item = h.add(ListItemNode.self, ["index": .integer(2)])
        h.wire(series, "values", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[12]")
    }

    @Test func aShortBranchContributesNothingAndTheNodeSaysSo() async throws {
        var h = Harness()
        let partition = rows(&h, count: 7, size: 3)
        let item = h.add(ListItemNode.self, ["index": .integer(2)])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[[2],[5],[]]")
        #expect(report.warning(item) == "1 of 3 branches have no item 2.")
    }

    @Test func listItemRefusesANegativeIndex() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let item = h.add(ListItemNode.self, ["index": .integer(-1)])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.error(item) == "“index” can't be negative. The first item is 0.")
    }

    // MARK: List Item by path

    @Test func anItemPathTakesTheOneItemAtThatPath() async throws {
        var h = Harness()
        let partition = rows(&h, count: 9, size: 3)
        let item = h.add(ListItemNode.self, [NodeSetting.itemPath: .text("{1;2}")])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[5]")
        #expect(report.isOK(item))
    }

    @Test func anItemPathOverridesTheIndex() async throws {
        var h = Harness()
        let partition = rows(&h, count: 9, size: 3)
        let item = h.add(ListItemNode.self, ["index": .integer(0), NodeSetting.itemPath: .text("{2;1}")])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[7]")
    }

    @Test func anItemPathOnAFlatListIsOneIndex() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(10), "count": .integer(4)])
        let item = h.add(ListItemNode.self, [NodeSetting.itemPath: .text("{3}")])
        h.wire(series, "values", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[13]")
    }

    @Test func aBlankItemPathMeansUseTheIndex() async throws {
        var h = Harness()
        let partition = rows(&h, count: 9, size: 3)
        let item = h.add(ListItemNode.self, ["index": .integer(1), NodeSetting.itemPath: .text("  ")])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.value(item, "item")?.outline == "[[1],[4],[7]]")
    }

    @Test func anItemPathMustNameABranchAndAnItem() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let item = h.add(ListItemNode.self, [NodeSetting.itemPath: .text("{1}")])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.error(item) == "{1} has 1 index, but an item of this tree (2 × 3) needs 2. Write it like {0;0}.")
    }

    @Test func anItemPathThatDoesNotReadIsNamed() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let item = h.add(ListItemNode.self, [NodeSetting.itemPath: .text("1;2")])
        h.wire(partition, "tree", to: item, "tree")
        let report = try await h.run([item])
        #expect(report.error(item) == "“1;2” isn't a path. Write it like {0;3}.")
    }

    @Test func aMissingBranchOrItemInAPathSaysHowManyThereAre() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let noBranch = h.add(ListItemNode.self, [NodeSetting.itemPath: .text("{4;0}")])
        let noItem = h.add(ListItemNode.self, [NodeSetting.itemPath: .text("{1;7}")])
        h.wire(partition, "tree", to: noBranch, "tree")
        h.wire(partition, "tree", to: noItem, "tree")
        let report = try await h.run([noBranch, noItem])
        #expect(report.error(noBranch) == "No branch {4}: the tree has 2 branches.")
        #expect(report.error(noItem) == "No item {1;7}: {1} has 3 items.")
        #expect(report.value(noItem, "item") == nil, "never a neighbour")
    }

    @Test func theItemsFeedAnItemInputLikeAnyList() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(1), "count": .integer(6)])
        let partition = h.add(PartitionNode.self, ["size": .integer(3)])
        h.wire(series, "values", to: partition, "tree")
        let item = h.add(ListItemNode.self, ["index": .integer(0)])
        h.wire(partition, "tree", to: item, "tree")
        let rectangle = h.add(RectangleNode.self, ["height": .number(5)])
        h.wire(item, "item", to: rectangle, "width")
        let report = try await h.run([rectangle])
        #expect(report.error(rectangle) == nil)
        #expect(report.value(rectangle, "profile")?.depth == 2)
        #expect(report.value(rectangle, "profile")?.items.count == 2)
    }

    // MARK: Branch by Path

    @Test func branchByPathTakesAWholeBranch() async throws {
        var h = Harness()
        let partition = rows(&h, count: 9, size: 3)
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{1}")])
        h.wire(partition, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.value(branch, "branch")?.outline == "[3,4,5]")
        guard case .list? = report.value(branch, "branch") else { Issue.record("expected a flat list"); return }
    }

    @Test func aNewNodeAsksForTheFirstBranch() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 2)
        let branch = h.add(BranchByPathNode.self)
        h.wire(partition, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.value(branch, "branch")?.outline == "[0,1]")
    }

    @Test func aDeeperTreeTakesALeafByAFullPathAndASubtreeByAShortOne() async throws {
        var h = Harness()
        let first = rows(&h, count: 8, size: 4)
        let second = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(first, "tree", to: second, "tree")
        let leaf = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{1;0}")])
        h.wire(second, "tree", to: leaf, "tree")
        let subtree = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{1}")])
        h.wire(second, "tree", to: subtree, "tree")
        let report = try await h.run([leaf, subtree])
        #expect(report.value(leaf, "branch")?.outline == "[4,5]")
        #expect(report.value(subtree, "branch")?.outline == "[[4,5],[6,7]]")
    }

    @Test func aFlatListsOnlyBranchIsTheEmptyPath() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(3)])
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{}")])
        h.wire(series, "values", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.value(branch, "branch")?.outline == "[0,1,2]")
    }

    @Test func aPathThatDoesNotReadIsNamed() async throws {
        var h = Harness()
        let partition = rows(&h, count: 4, size: 2)
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("one;two")])
        h.wire(partition, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.error(branch) == "“one;two” isn't a path. Write it like {0} or {1;3}.")
    }

    @Test func aPathWithTooManyIndicesNamesTheShapeAndAnExample() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{0;3}")])
        h.wire(partition, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.error(branch) == "{0;3} names a branch with 2 indices, but this tree's branches (2 × 3) have 1. Write it like {0}.")
    }

    @Test func aMissingBranchSaysHowManyThereAre() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{5}")])
        h.wire(partition, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.error(branch) == "No branch {5}: the tree has 2 branches.")
    }

    @Test func aMissingBranchDeeperDownNamesItsParent() async throws {
        var h = Harness()
        let first = rows(&h, count: 8, size: 4)
        let second = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(first, "tree", to: second, "tree")
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{1;7}")])
        h.wire(second, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.error(branch) == "No branch {1;7}: {1} has 2 branches.")
    }

    @Test func branchByPathNeverJumpsToANeighbour() async throws {
        var h = Harness()
        let partition = rows(&h, count: 6, size: 3)
        let branch = h.add(BranchByPathNode.self, [NodeSetting.branchPath: .text("{2}")])
        h.wire(partition, "tree", to: branch, "tree")
        let report = try await h.run([branch])
        #expect(report.value(branch, "branch") == nil)
    }
}
