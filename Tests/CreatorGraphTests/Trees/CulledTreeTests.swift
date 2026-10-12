import Testing
@testable import CreatorGraph

/// Culling keeps paths (patterns spec §4): a flat list or a branch that has had items taken out holds the survivors at
/// the indices they had, so item `{3}` is still `{3}` when `{1}` is gone. `Value.list` cannot say that, so a culled flat
/// list is a `Value.tree` of depth 1.
struct CulledTreeTests {
    func numbers(_ values: [Int]) -> [Scalar] { values.map { .integer($0) } }

    func culled(_ values: [Int], at positions: [Int]) throws -> DataTree {
        try #require(DataTree.culledList(numbers(values), at: positions))
    }

    // MARK: building

    @Test func positionsMustFitTheItems() {
        #expect(DataTree.culledList(numbers([1, 2]), at: [0]) == nil, "one position short")
        #expect(DataTree.culledList(numbers([1, 2]), at: [2, 1]) == nil, "they must increase")
        #expect(DataTree.culledList(numbers([1, 2]), at: [1, 1]) == nil, "no two items share an index")
        #expect(DataTree.culledList(numbers([1, 2]), at: [-1, 0]) == nil, "none is negative")
        #expect(DataTree.culledList([], at: []) != nil, "everything culled is still a culled list")
    }

    @Test func aCulledListKeepsItsIndicesAndItsItems() throws {
        let tree = try culled([10, 30, 40], at: [0, 2, 3])
        #expect(tree.isCulled)
        #expect(tree.depth == 1)
        #expect(tree.itemPositions == [0, 2, 3])
        #expect(tree.culledPositions == [0, 2, 3])
        #expect(tree.items.map(\.outlineText) == ["10", "30", "40"])
        #expect(tree.itemCount == 3)
    }

    @Test func aPlainListIsNotCulledAndNumbersItsItemsFromZero() {
        let tree = DataTree.list(numbers([5, 6, 7]))
        #expect(!tree.isCulled)
        #expect(tree.itemPositions == [0, 1, 2])
        #expect(tree.culledPositions == nil)
    }

    @Test func aListCulledOnlyAtTheEndIsStillCulledSoTheEndDoesNotComeBack() throws {
        let tree = try culled([1, 2], at: [0, 1])
        #expect(tree.isCulled)
        #expect(tree.itemPositions == [0, 1])
    }

    // MARK: values

    @Test func aCulledFlatListIsATreeValueAndAPlainOneIsAList() throws {
        if case .tree(let tree) = Value(try culled([1], at: [4])) { #expect(tree.depth == 1) } else { Issue.record("expected a tree") }
        #expect(Value(.list(numbers([1, 2]))).isList)
    }

    @Test func aCulledListHasDepthOneAndItsItemsInOrder() throws {
        let value = Value(try culled([7, 8], at: [1, 5]))
        #expect(value.depth == 1)
        #expect(value.items.map(\.outlineText) == ["7", "8"])
        #expect(value.asTree?.itemPositions == [1, 5])
    }

    @Test func convertingAValueKeepsTheIndices() throws {
        let value = Value(try culled([1, 2], at: [3, 9]))
        let converted = try #require(value.converted(to: .number))
        #expect(converted.asTree?.itemPositions == [3, 9])
        #expect(converted.items.allSatisfy { if case .number = $0 { true } else { false } })
    }

    @Test func theShapeSaysCulled() throws {
        #expect(try culled([1, 2, 3], at: [0, 2, 3]).shapeText == "3, culled")
        let deeper = try #require(DataTree(depth: 2, branches: [culled([1], at: [2]), .list(numbers([4, 5]))]))
        #expect(deeper.shapeText == "2 branches: 1, 2, culled")
        #expect(DataTree.list(numbers([1, 2])).shapeText == "2")
    }

    // MARK: branches

    @Test func leavesReportEachBranchsIndicesAndItemPaths() throws {
        let tree = try #require(DataTree(depth: 2, branches: [culled([1, 2], at: [0, 3]), .list(numbers([5])), .list([])]))
        let leaves = tree.leaves
        #expect(leaves.map(\.positions) == [[0, 3], [0], []])
        #expect(leaves.map(\.isCulled) == [true, false, false])
        #expect(leaves[0].itemPath(1) == TreePath([0, 3]))
        #expect(leaves[1].itemPath(0) == TreePath([1, 0]))
    }

    @Test func keepingItemsLeavesGapsAndNoRenumbering() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([0, 1, 2, 3])), .list(numbers([10, 11, 12]))]))
        let kept = tree.keepingItems { _, _, k in k != 1 }
        #expect(kept.outline == "[[0,2,3],[10,12]]")
        #expect(kept.leaves.map(\.positions) == [[0, 2, 3], [0, 2]])
        #expect(kept.isCulled)
    }

    @Test func keepingEverythingChangesNothingAndKeepsAPlainListPlain() {
        let tree = DataTree.list(numbers([1, 2, 3]))
        #expect(!tree.keepingItems { _, _, _ in true }.isCulled)
    }

    @Test func aBranchThatLosesEverythingStaysAsAnEmptyBranch() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([1])), .list(numbers([2, 3]))]))
        let kept = tree.keepingItems { leaf, _, _ in leaf.path != TreePath([0]) }
        #expect(kept.outline == "[[],[2,3]]")
        #expect(kept.leaves.map(\.positions) == [[], [0, 1]])
        #expect(kept.branches.count == 2)
    }

    @Test func aSecondCullKeepsTheFirstOnesIndices() throws {
        let first = DataTree.list(numbers([0, 1, 2, 3, 4])).keepingItems { _, _, k in k != 1 }
        let second = first.keepingItems { _, _, k in k != 0 }
        #expect(second.itemPositions == [2, 3, 4], "k counts the survivors, the indices stay the original ones")
        #expect(second.items.map(\.outlineText) == ["2", "3", "4"])
    }

    @Test func rebuildingNumbersTheBranchesThatHoldItemsEvenWhenEmpty() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list([]), .list(numbers([1])), .list(numbers([2]))]))
        var seen: [Int] = []
        _ = tree.rebuildingLeaves { leaf, ordinal in
            seen.append(ordinal)
            return (leaf.items, leaf.positions, leaf.isCulled)
        }
        #expect(seen == [0, 1, 2])
    }

    @Test func mappingItemsKeepsTheNestingAndTheIndices() throws {
        let tree = try #require(DataTree(depth: 2, branches: [culled([1, 2], at: [1, 4]), .list(numbers([3]))]))
        let replaced = tree.mappingItems { leaf, ordinal, k in .integer(ordinal * 100 + leaf.positions[k]) }
        #expect(replaced.outline == "[[1,4],[100]]")
        #expect(replaced.leaves.map(\.positions) == [[1, 4], [0]])
    }

    @Test func replacingItemsKeepsTheIndicesOfACulledList() throws {
        let flat = try culled([1, 2], at: [1, 4])
        let replaced = try #require(flat.replacingItems(numbers([8, 9])))
        #expect(replaced.isCulled && replaced.itemPositions == [1, 4])
        let deep = try #require(DataTree(depth: 2, branches: [culled([1], at: [2]), .list(numbers([3, 4]))]))
        #expect(try #require(deep.replacingItems(numbers([5, 6, 7]))).leaves.map(\.positions) == [[2], [0, 1]])
    }

    // MARK: broadcasting

    let specs = [SocketSpec("a", .number, access: .list), SocketSpec("b", .number)]

    @Test func aCulledListOnAListSocketRunsOnceAndGetsItsItems() throws {
        let plan = BroadcastPlan.make(inputs: ["a": Value(try culled([1, 2, 3], at: [0, 2, 5]))], specs: specs)
        #expect(!plan.isTreeRun)
        #expect(plan.iterations == 1)
        #expect(try plan.inputs(at: 0).list("a").count == 3, "a list socket sees the survivors in order, as a rank")
    }

    @Test func aCulledListOnAnItemSocketPairsItemsByTheirPlaceInTheList() throws {
        let reals = try #require(DataTree.culledList([5, 6, 7].map { .number(Double($0)) }, at: [1, 2, 8]))
        let plan = BroadcastPlan.make(inputs: ["a": .one(.number(0)), "b": Value(reals)], specs: specs)
        #expect(!plan.isTreeRun)
        #expect(plan.iterations == 3)
        #expect(try (0..<3).map { try plan.inputs(at: $0).number("b") } == [5, 6, 7])
    }

    @Test func aCulledListBesideARealTreeBroadcastsLikeAList() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([1, 2])), .list(numbers([3, 4]))]))
        let plan = BroadcastPlan.make(inputs: ["a": Value(try culled([1, 2], at: [0, 4])), "b": .tree(tree)], specs: specs)
        #expect(plan.isTreeRun)
        #expect(plan.iterations == 4)
        #expect(try plan.inputs(at: 3).list("a").count == 2)
    }

    @Test func aTreeAccessSocketGetsTheCulledTreeWhole() throws {
        let treeSpecs = [SocketSpec("t", .any, access: .tree)]
        let plan = BroadcastPlan.make(inputs: ["t": Value(try culled([1, 2], at: [3, 4]))], specs: treeSpecs)
        let tree = try plan.inputs(at: 0).tree("t")
        #expect(tree.itemPositions == [3, 4])
    }
}
