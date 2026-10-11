import Testing
@testable import CreatorGraph

struct DataTreePickingTests {
    @Test func pickingKeepsTheNestingAndCountsShortBranches() {
        let picked = rows([0, 1, 2], [3, 4], [5]).picking(itemAt: 1)
        #expect(picked.tree.outline == "[[1],[4],[]]")
        #expect(picked.missing == 1)
    }

    @Test func pickingFromAFlatListGivesOneItemOrNone() {
        #expect(DataTree.list(ints(7, 8)).picking(itemAt: 1).tree.outline == "[8]")
        #expect(DataTree.list(ints(7, 8)).picking(itemAt: 5).missing == 1)
    }

    @Test func pickingGoesDownToEveryLeaf() throws {
        let deep = try #require(DataTree(depth: 3, branches: [rows([0, 1], [2]), rows([3], [4, 5])]))
        let picked = deep.picking(itemAt: 1)
        #expect(picked.tree.outline == "[[[1],[]],[[],[5]]]")
        #expect(picked.missing == 2)
    }
}
