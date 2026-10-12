import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Culling keeps paths (patterns spec §4, §6) where instances are named: `InstanceGrid` makes exactly the instances a culled
/// list or branch holds, at the indices they had, and reads every other input at those indices.
struct InstanceGridCullTests {
    func numbers(_ values: Double...) -> DataTree { .list(values.map(Scalar.number)) }

    /// `values`, with only the items at `kept` left, as a Cull node leaves them.
    func culled(_ values: [Double], keeping kept: [Int]) throws -> DataTree {
        try #require(DataTree.culledList(kept.map { .number(values[$0]) }, at: kept))
    }

    func rows(_ rows: [[Double]]) throws -> DataTree {
        try #require(DataTree(depth: 2, branches: rows.map { .list($0.map(Scalar.number)) }))
    }

    func grid(_ trees: [(SocketName, DataTree)]) throws -> InstanceGrid {
        try InstanceGrid(trees.map { (name: $0.0, tree: $0.1) })
    }

    // MARK: A culled flat list

    @Test func aCulledListMakesExactlyTheInstancesItKeepsAtTheirIndices() throws {
        let grid = try grid([("placements", try culled([0, 10, 20, 30], keeping: [1, 3]))])
        #expect(grid.count == 2)
        #expect(grid.paths == [[1], [3]])
        #expect(grid.items == [1, 3], "a flat instance is named by its index, so {3} is still {3}")
        #expect(try grid.numbers("placements") == [10, 30])
    }

    @Test func aLongerListAddsNoInstancesToCulledOnes() throws {
        let grid = try grid([("placements", try culled([0, 1, 2, 3, 4], keeping: [0, 1])), ("size", numbers(5, 6, 7, 8, 9, 10))])
        #expect(grid.count == 2, "what was culled off the end stays gone")
        #expect(try grid.numbers("size") == [5, 6])
    }

    @Test func aSurvivorKeepsItsOwnSizeNotTheSizeOfItsRank() throws {
        let grid = try grid([("placements", try culled([0, 1, 2, 3], keeping: [1, 3])), ("size", numbers(10, 20, 30, 40))])
        #expect(try grid.numbers("size") == [20, 40])
    }

    @Test func aCulledSizeListIsReadByTheInstancesIndex() throws {
        let sizes = try culled([5, 0, 0, 9], keeping: [0, 3])
        let grid = try grid([("placements", numbers(0, 0, 0, 0)), ("size", sizes)])
        #expect(try grid.numbers("size") == [5, 5, 5, 9], "its own value at its index, else the nearest one before it")
        let late = try self.grid([("placements", numbers(0, 0, 0)), ("size", try culled([0, 0, 0, 7], keeping: [3]))])
        #expect(try late.numbers("size") == [7, 7, 7], "before its first survivor, the first")
    }

    @Test func aCulledSizeListWithMoreSurvivorsThanPlacementsSetsNoNumberOfInstances() throws {
        let sizes = try #require(DataTree.culledList(Array(repeating: Scalar.number(5), count: 10), at: Array(10..<20)))
        let grid = try grid([("placements", numbers(0, 0, 0, 0)), ("size", sizes)])
        #expect(grid.count == 4, "ten survivors do not make ten instances")
        #expect(grid.items == [0, 1, 2, 3])
    }

    @Test func aCulledSizeListWithNothingLeftMakesNoInstances() throws {
        let nothing = try #require(DataTree.culledList([], at: []))
        let grid = try grid([("placements", numbers(0, 0, 0)), ("size", nothing)])
        #expect(grid.count == 0)
    }

    @Test func everyPlacementCulledMakesNoInstancesAndGivesBackAnEmptyCulledList() throws {
        let grid = try grid([("placements", try #require(DataTree.culledList([], at: []))), ("size", numbers(1, 2))])
        #expect(grid.count == 0 && grid.items.isEmpty)
        let back = grid.tree(of: [])
        #expect(back.isCulled && back.itemCount == 0)
    }

    @Test func theOutputIsCulledAtTheSameIndices() throws {
        let grid = try grid([("placements", try culled([0, 1, 2, 3, 4], keeping: [0, 2, 3]))])
        let back = grid.tree(of: [.integer(7), .integer(8), .integer(9)])
        #expect(back.isCulled && back.itemPositions == [0, 2, 3])
        #expect(back.items.map(\.outlineText) == ["7", "8", "9"])
    }

    @Test func aPlainListIsStillPlain() throws {
        let grid = try grid([("placements", numbers(1, 2))])
        #expect(!grid.tree(of: [.integer(7), .integer(8)]).isCulled)
    }

    // MARK: A culled tree

    @Test func aCulledBranchKeepsItsIndicesInEveryPath() throws {
        let tree = try rows([[0, 1, 2, 3], [4, 5, 6]]).keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k == 1) }
        let grid = try grid([("placements", tree)])
        #expect(grid.paths == [[0, 0], [0, 2], [0, 3], [1, 0], [1, 1], [1, 2]], "{0;2} is still {0;2} with {0;1} gone")
        #expect(grid.items == grid.paths.compactMap { InstancePath.item(for: $0) })
        #expect(try grid.numbers("placements") == [0, 2, 3, 4, 5, 6])
    }

    @Test func aFlatListAppliesByIndexToACulledBranch() throws {
        let tree = try rows([[0, 0, 0, 0], [0, 0, 0]]).keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k == 1) }
        let grid = try grid([("placements", tree), ("size", numbers(10, 20, 30, 40))])
        #expect(try grid.numbers("size") == [10, 30, 40, 10, 20, 30], "{0;2} takes the third size, not the second")
    }

    @Test func aWholeBranchCulledLeavesAGapAndTheOthersKeepTheirNumbers() throws {
        let tree = try rows([[0, 0], [0, 0, 0]]).keepingItems { leaf, _, _ in leaf.path != TreePath([0]) }
        let grid = try grid([("placements", tree)])
        #expect(grid.paths == [[1, 0], [1, 1], [1, 2]])
        let back = grid.tree(of: grid.paths.map { _ in .integer(1) })
        #expect(back.outline == "[[],[1,1,1]]")
    }

    @Test func theOutputOfACulledTreeHasTheSameGaps() throws {
        let tree = try rows([[0, 0, 0, 0], [0, 0]]).keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k % 2 == 1) }
        let grid = try grid([("placements", tree)])
        let back = grid.tree(of: (0..<grid.count).map { .integer($0) })
        #expect(back.leaves.map(\.positions) == [[0, 2], [0, 1]])
        #expect(back.items.map(\.outlineText) == ["0", "1", "2", "3"])
    }

    @Test func aCulledTreeOfSizesIsReadAtTheInstancesPlace() throws {
        let sizes = try rows([[1, 2, 3], [4, 5, 6]]).keepingItems { _, _, k in k != 1 }
        let grid = try grid([("placements", try rows([[0, 0, 0], [0, 0, 0]])), ("size", sizes)])
        #expect(try grid.numbers("size") == [1, 1, 3, 4, 4, 6], "{r;1} takes the nearest size before it")
    }

    @Test func aCulledFirstItemInATreeOfSizesIsStoodInForByTheFirstSurvivor() throws {
        let sizes = try rows([[1, 2], [3, 4]]).keepingItems { _, _, k in k != 0 }
        let grid = try grid([("placements", try rows([[0, 0], [0, 0]])), ("size", sizes)])
        #expect(try grid.numbers("size") == [2, 2, 4, 4], "the first survivor stands in for the culled first item")
    }
}
