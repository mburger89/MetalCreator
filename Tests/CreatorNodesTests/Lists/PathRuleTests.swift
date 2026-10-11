import CreatorGraph
import Testing
@testable import CreatorNodes

struct PathRuleTests {
    /// Branches of integers, as a tree of depth 2.
    func rows(_ branches: [Int]...) -> DataTree {
        DataTree(depth: 2, branches: branches.map { .list($0.map { .integer($0) }) }) ?? .empty(depth: 2)
    }

    /// 2 × 3 × 2: the integers 0 to 11 in pairs, three pairs to a row, two rows.
    var deep: DataTree {
        let pairs = (0..<6).map { DataTree.list([.integer($0 * 2), .integer($0 * 2 + 1)]) }
        let rows = [Array(pairs[0..<3]), Array(pairs[3..<6])].compactMap { DataTree(depth: 2, branches: $0) }
        return DataTree(depth: 3, branches: rows) ?? .empty(depth: 3)
    }

    func map(_ rule: String, _ tree: DataTree) throws -> String {
        try PathRuleParser.parse(rule).apply(to: tree).tree.outline
    }

    func refusal(_ rule: String, _ tree: DataTree) -> String? {
        do {
            _ = try PathRuleParser.parse(rule).apply(to: tree)
            return nil
        } catch let error as PathRuleError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    // MARK: rules that work

    @Test func swappingRowsAndColumns() throws {
        #expect(try map("{A;B} → {B;A}", deep) == "[[[0,1],[6,7]],[[2,3],[8,9]],[[4,5],[10,11]]]")
    }

    @Test func mergingEachRow() throws {
        #expect(try map("{A;B} → {A}", deep) == "[[0,1,2,3,4,5],[6,7,8,9,10,11]]")
    }

    @Test func mergingEachColumn() throws {
        #expect(try map("{A;B} → {B}", deep) == "[[0,1,6,7],[2,3,8,9],[4,5,10,11]]")
    }

    @Test func foldingColumnsWithARemainder() throws {
        #expect(try map("{A;B} → {A;B%2}", deep) == "[[[0,1,4,5],[2,3]],[[6,7,10,11],[8,9]]]")
    }

    @Test func theItemIndexSendsEachItemToABranchOfItsOwnIndex() throws {
        #expect(try map("{A} → {(i)}", rows([0, 1], [2, 3], [4, 5])) == "[[0,2,4],[1,3,5]]")
    }

    @Test func theItemIndexAsALevelGraftsEachItem() throws {
        #expect(try map("{A} → {A;(i)}", rows([0, 1], [2, 3], [4, 5])) == "[[[0],[1]],[[2],[3]],[[4],[5]]]")
    }

    @Test func aFlatListHasTheEmptyPath() throws {
        #expect(try map("{} → {(i)/2}", .list((0..<6).map { .integer($0) })) == "[[0,1],[2,3],[4,5]]")
        #expect(try map("{} → {}", .list((0..<3).map { .integer($0) })) == "[0,1,2]")
    }

    @Test func gapsInTheResultAreEmptyBranches() throws {
        #expect(try map("{A} → {A*2+1}", rows([0, 1], [2, 3], [4, 5])) == "[[],[0,1],[],[2,3],[],[4,5]]")
    }

    @Test func theUnicodeOperatorsAndBracketsWork() throws {
        #expect(try map("{A} → {(A + 1) × 2 − 2}", rows([0, 1], [2, 3], [4, 5])) == "[[0,1],[],[2,3],[],[4,5]]")
        #expect(try map("{A} -> {A*2}", rows([0], [1])) == "[[0],[],[1]]")
    }

    @Test func spacesAreIgnored() throws {
        #expect(try map("  { A ; B }→{ B ; A }  ", deep) == "[[[0,1],[6,7]],[[2,3],[8,9]],[[4,5],[10,11]]]")
        #expect(try map("{A} → {( i )}", rows([0, 1], [2, 3])) == "[[0,2],[1,3]]")
    }

    @Test func aRepeatedLetterMatchesOnlyWhereTheIndicesAreEqual() throws {
        let result = try PathRuleParser.parse("{A;A} → {A;A}").apply(to: deep)
        #expect(result.matched == 2)
        #expect(result.total == 6)
        #expect(result.tree.outline == deep.outline, "the other four branches stay where they were")
    }

    @Test func aWholeNumberInTheSourceMatchesOnlyThatIndex() throws {
        let result = try PathRuleParser.parse("{0;B} → {B;0}").apply(to: deep)
        #expect(result.matched == 3)
        #expect(result.total == 6)
        #expect(result.tree.outline == "[[[0,1]],[[2,3,6,7],[8,9],[10,11]],[[4,5]]]")
        #expect(result.merged == 1, "{1;0} was left in place and the rule wrote its own {1;0}: [6,7] joined [2,3]")
    }

    @Test func branchesLeftInPlaceThatTheRuleDidNotWriteToAreNotMerged() throws {
        #expect(try PathRuleParser.parse("{A;A} → {A;A}").apply(to: deep).merged == 0)
    }

    @Test func aRuleThatMatchesEverythingReportsAllMatched() throws {
        let result = try PathRuleParser.parse("{A;B} → {B;A}").apply(to: deep)
        #expect(result.matched == 6 && result.total == 6)
    }

    @Test func anEmptyTreeGivesAnEmptyTree() throws {
        #expect(try map("{A} → {A;(i)}", .empty(depth: 2)) == "[]")
        #expect(try PathRuleParser.parse("{A} → {A;(i)}").apply(to: .empty(depth: 2)).tree.depth == 3)
    }

    // MARK: rules that don't read

    @Test(arguments: [
        ("", "The rule is empty. Write it like {A;B} → {B;A}."),
        ("{A;B}", "The rule needs → between the source and the target, like {A;B} → {B;A}."),
        ("{A} {A}", "The rule needs → between the source and the target, like {A;B} → {B;A}."),
        ("A → B", "The source must be a path in braces, like {A;B}."),
        ("{A} →", "The target must be a path in braces, like {A;B}."),
        ("{A} → {A", "The target path is missing its closing }."),
        ("{A", "The source path is missing its closing }."),
        ("{A;} → {A}", "Expected a number or letter but found “}” (character 4)."),
        ("{A} → {(A+1}", "A ( in the rule has no matching )."),
        ("{A} → {A} extra", "Unexpected “extra” after the target path."),
        ("{A} → {A$}", "Can't read “$” in the rule (character 9)."),
        ("{A B} → {A}", "Can't read “B” in the source path; separate the levels with ;."),
        ("{A;B} → {C}", "The target uses “C”, but the source {A;B} only names A, B."),
        ("{} → {A}", "The target uses “A”, but the source {} names no letters."),
        ("{i} → {i}", "“i” can't be a letter in the source: (i) is the item's index. Use another letter."),
        ("{(i)} → {A}", "“(i)” can only be used in the target, not in the source {(i)}."),
        ("{A+1} → {A}", "The source {A+1} can only have letters and whole numbers; “A+1” is a calculation."),
        ("{A} → {99999999999999999999}", "“99999999999999999999” is too large to be in a path."),
    ])
    func badRulesNameTheFailingPart(_ rule: String, _ message: String) {
        #expect(throws: PathRuleError(message)) { try PathRuleParser.parse(rule) }
    }

    // MARK: rules that don't fit the tree

    @Test func aSourceWithTwoOrMoreLettersTooManyOrTooFewSaysHowManyLevelsTheTreeHas() {
        #expect(refusal("{A;B;C} → {A}", rows([1, 2], [3, 4], [5, 6]))
                == "The rule's source {A;B;C} names 3 levels, but this tree (3 × 2) has 1 level of branches. "
                + "Write the source with 1 level, like {A}, or with 2, like {A;B}, to name items too.")
        #expect(refusal("{A;B} → {A}", .list([.integer(1)]))
                == "The rule's source {A;B} names 2 levels, but this tree (1) has 0 levels of branches. "
                + "Write the source with 0 levels, like {}, or with 1, like {A}, to name items too.")
        #expect(refusal("{A} → {A}", deep)
                == "The rule's source {A} names 1 level, but this tree (2 × 3 × 2) has 2 levels of branches. "
                + "Write the source with 2 levels, like {A;B}, or with 3, like {A;B;C}, to name items too.")
    }

    @Test func anItemRuleWhoseTargetIsNeitherTheBranchesNorTheBranchesAndAPositionIsRefused() {
        #expect(refusal("{A;B} → {A;B;0}", grid)
                == "The target {A;B;0} has 3 levels. A source that names items takes a target with 1 level "
                + "(the branch) or 2 (the branch and the position in it).")
    }

    @Test func aDivisionByZeroNamesTheTerm() {
        #expect(refusal("{A} → {A/0}", rows([1], [2])) == "“A/0” divides by zero.")
        #expect(refusal("{A} → {A%(A-A)}", rows([1], [2])) == "“A%(A-A)” divides by zero.")
    }

    @Test func aNegativeIndexNamesTheTermAndTheBranch() {
        #expect(refusal("{A} → {A-1}", rows([1], [2]))
                == "“A-1” gives -1 for the branch {0}, and a path can't have a negative index.")
    }

    @Test func aNumberTooLargeIsRefused() {
        #expect(refusal("{A} → {9999999999*9999999999}", rows([1]))
                == "“9999999999*9999999999” gives a number too large for a path.")
    }

    @Test func aRuleMakingTooManyBranchesIsRefused() {
        #expect(refusal("{A} → {A*100000}", rows([1], [2])) == "The rule makes more than 10,000 branches.")
    }

    @Test func unmatchedBranchesCannotStayWhenTheRuleChangesTheDepth() {
        #expect(refusal("{0;B} → {B}", deep)
                == "The rule changes how deep the tree is, so the 3 branches it doesn't match can't stay where they were. "
                + "Make every branch match, or give the target 2 levels.")
    }

    // MARK: sources that name items (User decision 2, option c)

    /// 3 × 4: the integers 0 to 11 in three rows.
    var grid: DataTree { rows([0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11]) }

    @Test func swappingRowsAndColumnsOfAGridNamesItems() throws {
        let result = try PathRuleParser.parse("{A;B} → {B;A}").apply(to: grid)
        #expect(result.tree.outline == "[[0,4,8],[1,5,9],[2,6,10],[3,7,11]]")
        #expect(result.tree.shapeText == "4 × 3")
        #expect(result.matched == 12 && result.total == 12 && result.merged == 0)
    }

    @Test func keepingTheRowsOfAGridNamesItems() throws {
        #expect(try map("{A;B} → {A}", grid) == "[[0,1,2,3],[4,5,6,7],[8,9,10,11]]")
        #expect(try map("{A;B} → {A;B}", grid) == "[[0,1,2,3],[4,5,6,7],[8,9,10,11]]")
    }

    @Test func gatheringTheColumnsOfAGridNamesItems() throws {
        #expect(try map("{A;B} → {B%2}", grid) == "[[0,2,4,6,8,10],[1,3,5,7,9,11]]")
    }

    @Test func thePositionOrdersTheItemsOfABranch() throws {
        #expect(try map("{A;B} → {0;3-B}", rows([0, 1, 2, 3])) == "[[3,2,1,0]]")
    }

    @Test func aRepeatedLetterMatchesItemsAndTheRestStayInTheirOwnBranch() throws {
        let diagonal = try PathRuleParser.parse("{A;A} → {0}").apply(to: grid)
        #expect(diagonal.tree.outline == "[[0,1,2,3,5,10],[4,6,7],[8,9,11]]")
        #expect(diagonal.matched == 3, "three items are on the diagonal and moved")
        #expect(diagonal.total == 12)
        #expect(diagonal.countsItems)
        #expect(diagonal.merged == 1, "the left-in-place items of {0} joined the diagonal")
    }

    @Test func aTrailingEmptyBranchSurvivesAnItemRule() throws {
        let sparse = try #require(DataTree(depth: 2, branches: [.list([.integer(1)]), .list([])]))
        #expect(try map("{A;B} → {A;B}", sparse) == "[[1],[]]")
        #expect(try map("{A;B} → {A}", sparse) == "[[1],[]]")
    }

    @Test func aFlatListWithOneLetterNamesItemsAndTheTargetIsTheirPosition() throws {
        #expect(try map("{A} → {A%2}", .list((0..<6).map { .integer($0) })) == "[0,2,4,1,3,5]")
    }
}
