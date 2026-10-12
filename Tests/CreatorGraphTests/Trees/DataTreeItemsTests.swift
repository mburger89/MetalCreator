import Testing
@testable import CreatorGraph

struct DataTreeItemsTests {
    func tree(_ rows: [[Int]]) -> DataTree {
        DataTree(depth: 2, branches: rows.map { .list($0.map(Scalar.integer)) }) ?? .empty(depth: 2)
    }

    @Test func replacingItemsKeepsTheShapeAndTheGaps() throws {
        let original = tree([[1, 2], [], [3, 4, 5]])
        let replaced = try #require(original.replacingItems((10...14).map(Scalar.integer)))
        #expect(replaced.leaves.map(\.path.indices) == [[0], [1], [2]])
        #expect(replaced.leaves.map { $0.items.count } == [2, 0, 3])
        #expect(replaced.items.compactMap { if case .integer(let value) = $0 { value } else { nil } } == [10, 11, 12, 13, 14])
    }

    @Test func aFlatListAndADeeperTreeKeepTheirDepth() throws {
        let flat = try #require(DataTree.list([.integer(1), .integer(2)]).replacingItems([.integer(7), .integer(8)]))
        #expect(flat.depth == 1)
        let deep = DataTree(depth: 3, branches: [tree([[1], [2, 3]])]) ?? .empty(depth: 3)
        let replaced = try #require(deep.replacingItems((0..<3).map(Scalar.integer)))
        #expect(replaced.depth == 3 && replaced.itemCount == 3)
    }

    @Test func aWrongNumberOfItemsGivesNothing() {
        #expect(tree([[1, 2]]).replacingItems([.integer(1)]) == nil)
        #expect(tree([[1, 2]]).replacingItems([]) == nil)
    }
}
