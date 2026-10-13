import Testing
@testable import CreatorGraph

/// What a tooltip or the inspector says about the field a value holds.
struct ValueFieldSummaryTests {
    @Test func oneFieldIsItsRecipe() {
        let field = Field.add(.constant(1), .constant(2))
        #expect(Value.one(.field(field)).fieldSummary() == "1 + 2")
        #expect(Value.list([.field(field)]).fieldSummary() == "1 + 2")
    }

    @Test func severalFieldsAreCountedAndAnythingElseHasNoSummary() {
        #expect(Value.list([.field(.constant(1)), .field(.constant(2)), .field(.constant(3))]).fieldSummary() == "3 fields")
        #expect(Value.one(.number(1)).fieldSummary() == nil)
        #expect(Value.list([]).fieldSummary() == nil)
        #expect(Value.list([.field(.constant(1)), .number(2)]).fieldSummary() == nil, "a mixed list is not a list of fields")
    }

    @Test func aLimitCutsTheRecipe() {
        var field = Field.constant(1)
        for step in 1...30 { field = .add(field, .constant(Double(step))) }
        let summary = Value.one(.field(field)).fieldSummary(limit: 80)
        #expect(summary?.count == 80 && summary?.hasSuffix("…") == true)
        #expect(Value.one(.field(field)).fieldSummary() == field.description)
        #expect(Value.list([.field(field), .field(field)]).fieldSummary(limit: 80) == "2 fields")
    }

    @Test func aTreeOfFieldsIsCountedToo() {
        let tree = DataTree.list([.field(.constant(1)), .field(.constant(2))])
        #expect(Value.tree(tree).fieldSummary() == "2 fields")
    }
}
