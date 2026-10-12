import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// How a pattern node matches its placements and sizes (patterns spec §3, §5 and §6): flat lists as before trees, trees
/// level by level, and a path for every instance.
struct InstanceGridTests {
    func numbers(_ values: Double...) -> DataTree { .list(values.map(Scalar.number)) }

    func rows(_ rows: [[Double]]) -> DataTree {
        DataTree(depth: 2, branches: rows.map { .list($0.map(Scalar.number)) }) ?? .empty(depth: 2)
    }

    func grid(_ trees: [(SocketName, DataTree)]) throws -> InstanceGrid {
        try InstanceGrid(trees.map { (name: $0.0, tree: $0.1) })
    }

    // MARK: Flat lists, as before trees

    @Test func flatListsMakeAsManyInstancesAsTheLongestAndTheShorterRepeatsItsLast() throws {
        let grid = try grid([("a", numbers(1, 2, 3)), ("b", numbers(10, 20, 30, 40, 50))])
        #expect(grid.count == 5)
        #expect(grid.paths == [[0], [1], [2], [3], [4]])
        #expect(try grid.numbers("a") == [1, 2, 3, 3, 3])
        #expect(try grid.numbers("b") == [10, 20, 30, 40, 50])
    }

    @Test func aFlatInstanceIsNamedByItsIndexAsItAlwaysWas() throws {
        let grid = try grid([("a", numbers(1, 2, 3))])
        #expect(grid.items == [0, 1, 2])
    }

    @Test func aSingleValueRepeatsForEveryInstance() throws {
        let grid = try grid([("a", numbers(1, 2)), ("b", numbers(7))])
        #expect(try grid.numbers("b") == [7, 7])
    }

    @Test func anInputWithNoItemsMakesNoInstances() throws {
        let grid = try grid([("a", numbers(1, 2)), ("b", .list([]))])
        #expect(grid.count == 0 && grid.items.isEmpty)
        #expect(grid.tree(of: []).depth == 1)
    }

    @Test func aFlatPatternGivesItsOutputsBackAsAFlatList() throws {
        let grid = try grid([("a", numbers(1, 2))])
        let tree = grid.tree(of: [.integer(5), .integer(6)])
        #expect(tree.depth == 1 && tree.items.count == 2)
    }

    // MARK: Trees

    @Test func theItemsOfATreeAreTheInstancesAndEachIsNamedByItsPath() throws {
        let grid = try grid([("placements", rows([[1, 2, 3], [4, 5]]))])
        #expect(grid.paths == [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1]])
        #expect(grid.items == grid.paths.compactMap { InstancePath.item(for: $0) })
        #expect(grid.items.allSatisfy { $0 < 0 })
        #expect(try grid.numbers("placements") == [1, 2, 3, 4, 5])
    }

    @Test func aFlatListAppliesToEveryBranchAndMatchesItsItems() throws {
        let grid = try grid([("placements", rows([[0, 0, 0], [0, 0]])), ("size", numbers(10, 20, 30))])
        #expect(try grid.numbers("size") == [10, 20, 30, 10, 20])
    }

    @Test func aSingleValueAppliesToEveryInstanceOfATree() throws {
        let grid = try grid([("placements", rows([[0, 0], [0]])), ("size", numbers(4))])
        #expect(try grid.numbers("size") == [4, 4, 4])
    }

    @Test func aTreeOfOneValuePerBranchGivesEachRingItsOwnValue() throws {
        // Graft of [8, 5]: branches {0} = [8] and {1} = [5].
        let perRing = rows([[8], [5]])
        let grid = try grid([("placements", rows([[0, 0, 0], [0, 0]])), ("diameter", perRing)])
        #expect(try grid.numbers("diameter") == [8, 8, 8, 5, 5])
    }

    @Test func aShorterTreeRepeatsItsLastBranch() throws {
        let grid = try grid([("placements", rows([[0], [0], [0]])), ("size", rows([[1], [2]]))])
        #expect(try grid.numbers("size") == [1, 2, 2])
    }

    @Test func aDeeperInputSetsTheShapeAndAFlatPlacementListFollowsIt() throws {
        let grid = try grid([("placements", numbers(100, 200)), ("size", rows([[1, 2, 3], [4]]))])
        #expect(grid.paths == [[0, 0], [0, 1], [0, 2], [1, 0]])
        #expect(try grid.numbers("placements") == [100, 200, 200, 100])
    }

    @Test func theOutputKeepsTheShapeIncludingEmptyBranches() throws {
        let grid = try grid([("placements", rows([[1, 2], [], [3]]))])
        let tree = grid.tree(of: (0..<3).map(Scalar.integer))
        #expect(tree.depth == 2)
        #expect(tree.leaves.map { $0.items.count } == [2, 0, 1])
    }

    @Test func aTreeWithEmptyBranchesOnlyMakesInstancesFromTheItemsItHas() throws {
        let grid = try grid([("placements", rows([[1], [], [2, 3]]))])
        #expect(grid.paths == [[0, 0], [2, 0], [2, 1]])
    }

    @Test func aTreeInputWithNoItemsAtAllMakesNoInstancesAndAnEmptyTree() throws {
        let grid = try grid([("placements", rows([[1, 2]])), ("size", .empty(depth: 2))])
        #expect(grid.count == 0)
        #expect(grid.tree(of: []).depth == 2)
    }

    // MARK: What can't be matched

    @Test func treesOfDifferentDepthsAreRefusedNamingBothShapes() throws {
        let deep = DataTree(depth: 3, branches: [rows([[1, 2]]), rows([[3, 4]])]) ?? .empty(depth: 3)
        #expect(throws: NodeError.invalidValue("“placements” (1 × 2) and “size” (2 × 1 × 2) are nested differently. "
            + "Use a flat list, or trees of the same depth.")) {
            _ = try grid([("size", deep), ("placements", rows([[1, 2]]))])
        }
    }

    @Test func aBranchWithNoItemsToTakeFromIsRefusedNamingItsPath() {
        #expect(throws: NodeError.invalidValue("“size” has no items for the branch {1}.")) {
            _ = try grid([("placements", rows([[1], [2]])), ("size", rows([[5], []]))])
        }
    }

    @Test func aPathThatCannotBeNamedIsRefused() {
        let wide = DataTree(depth: 2, branches: (0...InstancePath.maximumIndex + 1).map { _ in .list([.integer(1)]) }) ?? .empty(depth: 2)
        #expect(throws: NodeError.self) { _ = try grid([("placements", wide)]) }
    }

    @Test func moreInstancesThanThePatternLimitAreRefusedInAFlatListAndInATree() {
        let flat = DataTree.list((0..<2_001).map { Scalar.integer($0) })
        #expect(throws: NodeError.invalidValue("Patterns are limited to 2,000 instances.")) { _ = try grid([("a", flat)]) }
        let tree = DataTree(depth: 2, branches: [flat]) ?? .empty(depth: 2)
        #expect(throws: NodeError.invalidValue("Patterns are limited to 2,000 instances.")) { _ = try grid([("a", tree)]) }
    }

    @Test func aValueOfTheWrongTypeNamesTheSocket() throws {
        let grid = try grid([("a", numbers(1))])
        #expect(throws: NodeError.typeMismatch("a", expected: .bool)) { _ = try grid.bools("a") }
    }
}
