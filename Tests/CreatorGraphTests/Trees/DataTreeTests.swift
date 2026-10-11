import Testing
@testable import CreatorGraph

struct DataTreeTests {
    @Test func aListIsATreeOfDepthOne() {
        let list = DataTree.list(ints(1, 2, 3))
        #expect(list.depth == 1)
        #expect(list.count == 3)
        #expect(list.itemCount == 3)
        #expect(list.leaves.map(\.path) == [TreePath()])
    }

    @Test func branchesMustBeOneLevelShallower() {
        #expect(DataTree(depth: 2, branches: [.list(ints(1))]) != nil)
        #expect(DataTree(depth: 3, branches: [.list(ints(1))]) == nil)
        #expect(DataTree(depth: 1, branches: []) == nil)
        #expect(DataTree(depth: 2, branches: [rows([1])]) == nil)
    }

    @Test func itemsRunBranchByBranch() {
        let tree = rows([0, 1], [2, 3], [4])
        #expect(tree.items.map(\.outlineText) == ["0", "1", "2", "3", "4"])
        #expect(tree.itemCount == 5)
        #expect(tree.count == 3)
        #expect(tree.outline == "[[0,1],[2,3],[4]]")
    }

    @Test func leavesCarryTheirPaths() {
        let tree = rows([0, 1], [], [4])
        #expect(tree.leaves.map(\.path.description) == ["{0}", "{1}", "{2}"])
        #expect(tree.leaves.map(\.items.count) == [2, 0, 1])
    }

    @Test func aBranchIsFoundByPath() throws {
        let tree = rows([0, 1], [2, 3])
        #expect(try #require(tree.branch(at: TreePath([1]))).outline == "[2,3]")
        #expect(try #require(tree.branch(at: TreePath())).outline == "[[0,1],[2,3]]")
        #expect(tree.branch(at: TreePath([2])) == nil)
        #expect(tree.branch(at: TreePath([0, 0])) == nil)
    }

    @Test func flatteningKeepsTheRequestedOuterLevels() throws {
        let inner = try #require(DataTree(depth: 3, branches: [rows([0, 1], [2]), rows([3], [4, 5])]))
        #expect(inner.outline == "[[[0,1],[2]],[[3],[4,5]]]")
        #expect(inner.flattened(keeping: 0).outline == "[0,1,2,3,4,5]")
        #expect(inner.flattened(keeping: 1).outline == "[[0,1,2],[3,4,5]]")
        #expect(inner.flattened(keeping: 2).outline == inner.outline)
        #expect(inner.flattened(keeping: 9).outline == inner.outline)
        #expect(inner.flattened(keeping: -1).outline == "[0,1,2,3,4,5]")
    }

    @Test func graftingPutsEveryItemInItsOwnBranch() {
        #expect(DataTree.list(ints(1, 2)).grafted().outline == "[[1],[2]]")
        #expect(rows([1, 2], [3]).grafted().outline == "[[[1],[2]],[[3]]]")
        #expect(rows([1, 2], [3]).grafted().depth == 3)
    }

    @Test func partitioningSplitsEachListAndTheLastMayBeShort() {
        #expect(DataTree.list(ints(0..<5)).partitioned(size: 2).outline == "[[0,1],[2,3],[4]]")
        #expect(rows([0, 1, 2], [3]).partitioned(size: 2).outline == "[[[0,1],[2]],[[3]]]")
        #expect(DataTree.list([]).partitioned(size: 3).outline == "[]")
        #expect(DataTree.list(ints(1, 2)).partitioned(size: 0).outline == "[[1],[2]]")
    }

    @Test func rectangularTreesShowTheirSize() {
        #expect(rows([1, 2], [3, 4], [5, 6]).shapeText == "3 × 2")
        #expect(DataTree.list(ints(0..<8)).shapeText == "8")
        #expect(DataTree.empty(depth: 2).shapeText == "0 × 0")
    }

    @Test func raggedTreesListTheirBranchCounts() {
        #expect(rows([1, 2, 3], [4], [5, 6, 7]).shapeText == "3 branches: 3, 1, 3")
        #expect(rows([1], [2, 3]).dimensions == nil)
    }

    @Test func aLongRaggedListIsCutShort() {
        let tree = rows([1], [1, 2], [1], [1, 2], [1], [1, 2], [1], [1, 2])
        #expect(tree.shapeText == "8 branches: 1, 2, 1, 2, 1, 2, …")
    }

    @Test func conversionAppliesToEveryItemOrFails() {
        let converted = rows([1, 2], [3]).mapItems { $0.converted(to: .number) }
        #expect(converted?.items.allSatisfy { if case .number = $0 { true } else { false } } == true)
        #expect(rows([1]).mapItems { $0.converted(to: .solid) } == nil)
    }
}
