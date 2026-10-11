import Testing
@testable import CreatorGraph

struct TreeValueTests {
    @Test func depthCountsTheIndicesAnItemHas() {
        #expect(Value.one(.integer(1)).depth == 0)
        #expect(Value.list(ints(1, 2)).depth == 1)
        #expect(Value.tree(rows([1], [2])).depth == 2)
    }

    @Test func aFlatTreeBecomesAList() {
        guard case .list(let scalars) = Value(DataTree.list(ints(1, 2))) else { Issue.record("expected a list"); return }
        #expect(scalars.count == 2)
        guard case .tree = Value(rows([1])) else { Issue.record("expected a tree"); return }
    }

    @Test func itemsFlattenATree() {
        #expect(Value.tree(rows([0, 1], [2])).items.map(\.outlineText) == ["0", "1", "2"])
    }

    @Test func asTreeGivesAListItsOneLevel() {
        #expect(Value.list(ints(1, 2)).asTree?.outline == "[1,2]")
        #expect(Value.one(.integer(1)).asTree == nil)
        #expect(Value.tree(rows([1])).asTree?.outline == "[[1]]")
    }

    @Test func treesConvertItemByItem() {
        let value = Value.tree(rows([1, 2], [3]))
        #expect(value.converted(to: .number)?.depth == 2)
        #expect(value.converted(to: .solid) == nil)
    }

    @Test func shapesReadNextToASocket() {
        #expect(Value.one(.integer(1)).shapeText == "1 item")
        #expect(Value.list(ints(1)).shapeText == "1 item")
        #expect(Value.list(ints(1, 2)).shapeText == "2 items")
        #expect(Value.tree(rows([1, 2], [3, 4], [5, 6])).shapeText == "3 × 2")
    }

    @Test func aTreeCostsMoreThanItsItems() {
        #expect(Value.tree(rows([1, 2], [3])).estimatedBytes > Value.list(ints(1, 2, 3)).estimatedBytes)
    }
}
