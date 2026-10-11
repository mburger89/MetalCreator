import Testing
@testable import CreatorGraph

struct TreeBroadcastTests {
    let specs = [SocketSpec("a", .number), SocketSpec("b", .number), SocketSpec("all", .number, access: .list)]

    func numbers(_ plan: BroadcastPlan, _ name: SocketName) throws -> [Double] {
        try (0..<plan.iterations).map { try plan.inputs(at: $0).number(name) }
    }

    func tree(_ branches: [[Int]]) -> Value {
        .tree(DataTree(depth: 2, branches: branches.map { .list($0.map { .number(Double($0)) }) }) ?? .empty(depth: 2))
    }

    // MARK: level by level

    @Test func equalTreesPairItemForItem() throws {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1, 2], [3, 4, 5]]), "b": tree([[10, 11, 12], [13, 14, 15]])], specs: specs)
        #expect(plan.iterations == 6)
        #expect(try numbers(plan, "a") == [0, 1, 2, 3, 4, 5])
        #expect(try numbers(plan, "b") == [10, 11, 12, 13, 14, 15])
        #expect(plan.warning == nil)
    }

    @Test func aShorterSideRepeatsItsLastBranchAndItsLastItem() throws {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1, 2], [3, 4, 5], [6, 7, 8]]), "b": tree([[10, 11], [20]])],
                                      specs: specs)
        #expect(try numbers(plan, "b") == [10, 11, 11, 20, 20, 20, 20, 20, 20])
    }

    @Test func aSingleItemAppliesToEveryBranch() throws {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1], [2, 3]]), "b": .one(.number(5))], specs: specs)
        #expect(try numbers(plan, "b") == [5, 5, 5, 5])
    }

    @Test func aFlatListAppliesToEveryBranchAndMatchesItsItems() throws {
        let flat = Value.list([.number(10), .number(20), .number(30)])
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1, 2], [3, 4, 5]]), "b": flat], specs: specs)
        #expect(try numbers(plan, "b") == [10, 20, 30, 10, 20, 30])
    }

    @Test func outputsKeepTheDeepestInputsNesting() {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1], [2, 3], [4]]), "b": .one(.number(1))], specs: specs)
        let results = (0..<plan.iterations).map { [Scalar.integer($0)] }
        #expect(plan.assemble(results, producedList: false).outline == "[[0,1],[2,3],[4]]")
    }

    @Test func anEmptyBranchStaysEmptyInTheOutput() {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[], [7, 8]]), "b": .one(.number(1))], specs: specs)
        #expect(plan.iterations == 2)
        let results = (0..<plan.iterations).map { [Scalar.integer($0)] }
        #expect(plan.assemble(results, producedList: false).outline == "[[],[0,1]]")
    }

    @Test func anEmptyTreeMeansNoRuns() {
        let plan = BroadcastPlan.make(inputs: ["a": .tree(.empty(depth: 2)), "b": .one(.number(1))], specs: specs)
        #expect(plan.iterations == 0)
        #expect(plan.assemble([], producedList: false).outline == "[]")
    }

    @Test func aListOutputJoinsWithinEachInnermostBranch() {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1], [2]])], specs: specs)
        let results = [[Scalar.integer(1), .integer(2)], [.integer(3)], [.integer(4), .integer(5)]]
        #expect(plan.assemble(results, producedList: true).outline == "[[1,2,3],[4,5]]")
    }

    @Test func threeLevelsAgainstTwoMatchOutermostFirstThenTheFlatListsMeet() throws {
        let deep = DataTree(depth: 3, branches: [tree([[0, 1], [2]]).asTree, tree([[3], [4, 5]]).asTree].compactMap { $0 })
        let plan = BroadcastPlan.make(inputs: ["a": .tree(deep ?? .empty(depth: 3)), "b": tree([[100, 101], [200, 201]])], specs: specs)
        // Branch 0 of b ([100, 101]) is a flat list, so it applies to each of a's sub-branches and matches their items.
        #expect(plan.iterations == 8)
        #expect(try numbers(plan, "a") == [0, 1, 2, 2, 3, 3, 4, 5])
        #expect(try numbers(plan, "b") == [100, 101, 100, 101, 200, 201, 200, 201])
        #expect(plan.warning != nil)
    }

    // MARK: sockets that take lists

    @Test func aListSocketTakesOneBranchPerRun() throws {
        let plan = BroadcastPlan.make(inputs: ["all": tree([[1, 2, 3], [4, 5]])], specs: specs)
        #expect(plan.iterations == 2)
        #expect(try plan.inputs(at: 0).list("all").count == 3)
        #expect(try plan.inputs(at: 1).list("all").count == 2)
        let results = (0..<plan.iterations).map { [Scalar.integer($0)] }
        #expect(plan.assemble(results, producedList: false).outline == "[0,1]")
    }

    @Test func aListSocketOnATreeOfThreeLevelsKeepsTwo() {
        let deep = DataTree(depth: 3, branches: [tree([[1], [2]]).asTree, tree([[3], [4]]).asTree].compactMap { $0 })
        let plan = BroadcastPlan.make(inputs: ["all": .tree(deep ?? .empty(depth: 3))], specs: specs)
        #expect(plan.iterations == 4)
        let results = (0..<plan.iterations).map { [Scalar.integer($0)] }
        #expect(plan.assemble(results, producedList: false).outline == "[[0,1],[2,3]]")
    }

    @Test func aFlatListOnAListSocketStaysWhole() throws {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1], [2, 3]]), "all": .list([.number(7), .number(8)])], specs: specs)
        #expect(plan.iterations == 4)
        #expect(try plan.inputs(at: 3).list("all").count == 2)
    }

    /// User decision 3: a flat list on an item socket meets the branches of a tree on a list socket one for one (three
    /// plates against three rows), where against a tree on an item socket it applies to every branch
    /// (`aFlatListAppliesToEveryBranchAndMatchesItsItems`). Both follow one rule: a flat list steps only when it is as
    /// deep as the deepest input left, and a list socket's tree has used one of its levels up.
    @Test func aFlatListOnAnItemSocketPairsWithTheBranchesOfATreeOnAListSocket() throws {
        let flat = Value.list([.number(1), .number(2), .number(3)])
        let plan = BroadcastPlan.make(inputs: ["a": flat, "all": tree([[10, 11], [20]])], specs: specs)
        #expect(plan.iterations == 3)
        #expect(try numbers(plan, "a") == [1, 2, 3])
        #expect(try (0..<3).map { try plan.inputs(at: $0).list("all").count } == [2, 1, 1], "the shorter side repeats its last branch")
        #expect(plan.warning == nil)
    }

    @Test func itemTreesAndListTreesMatchFromTheOutside() throws {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1], [2, 3], [4, 5]]), "all": tree([[10], [20, 21], [30]])], specs: specs)
        #expect(plan.iterations == 6)
        #expect(try plan.inputs(at: 0).list("all").count == 1)
        #expect(try plan.inputs(at: 2).list("all").count == 2)
        #expect(try plan.inputs(at: 5).list("all").count == 1)
        #expect(plan.warning == nil)
    }

    // MARK: warnings and limits

    /// User decision 4: trees of different depth always warn, even when the shallower one nests at the outer levels
    /// (2 × 2 against 2 × 2 × 1, whose outer level agrees): the plan never judges which depths "nest".
    @Test func nestingThatDoesNotLineUpWarnsOnceNamingBothShapes() throws {
        let three = DataTree(depth: 3, branches: [tree([[1], [2]]).asTree, tree([[3], [4]]).asTree].compactMap { $0 })
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1], [2, 3]]), "b": .tree(three ?? .empty(depth: 3))], specs: specs)
        let warning = try #require(plan.warning)
        #expect(warning.contains("“a” (2 × 2)"))
        #expect(warning.contains("“b” (2 × 2 × 1)"))
    }

    @Test func sameDepthTreesDoNotWarnWhateverTheirSizes() {
        let plan = BroadcastPlan.make(inputs: ["a": tree([[0, 1, 2]]), "b": tree([[1], [2], [3]])], specs: specs)
        #expect(plan.warning == nil)
    }

    @Test func lopsidedTreesAreRefusedBeforeTheyHangAnything() throws {
        let tall = Value.tree(DataTree(depth: 2, branches: (0..<1000).map { _ in .list([.number(0)]) }) ?? .empty(depth: 2))
        let wide = Value.tree(DataTree(depth: 2, branches: [.list((0..<1000).map { .number(Double($0)) })]) ?? .empty(depth: 2))
        let plan = BroadcastPlan.make(inputs: ["a": tall, "b": wide], specs: specs)
        let refusal = try #require(plan.refusal)
        #expect(plan.iterations == 0)
        #expect(refusal.contains("100,000"))
        #expect(refusal.contains("“a” is 1,000 × 1"))
        #expect(refusal.contains("“b” is 1 × 1,000"))
    }

    // MARK: flat inputs are the same on either path

    @Test(arguments: [
        (Value.list([.number(1), .number(2), .number(3)]), Value.list([.number(10), .number(20)])),
        (Value.one(.number(1)), Value.list([.number(10), .number(20), .number(30), .number(40)])),
        (Value.list([.number(1), .number(2)]), Value.one(.number(5))),
        (Value.list([.number(1)]), Value.list([.number(10)])),
    ])
    func flatInputsGiveTheSameRunsOnTheNestedPath(_ a: Value, _ b: Value) throws {
        let inputs: [SocketName: Value] = ["a": a, "b": b, "all": .list([.number(9), .number(8)])]
        let flat = BroadcastPlan.make(inputs: inputs, specs: specs)
        let nested = BroadcastPlan.nestedPlan(inputs: inputs, specs: specs)
        #expect(nested.iterations == flat.iterations)
        #expect(try numbers(nested, "a") == numbers(flat, "a"))
        #expect(try numbers(nested, "b") == numbers(flat, "b"))
        #expect(try nested.inputs(at: 0).list("all").count == 2)
    }

    @Test func anEmptyFlatListMeansNoRunsOnEitherPath() {
        let inputs: [SocketName: Value] = ["a": .list([]), "b": .one(.number(5))]
        #expect(BroadcastPlan.make(inputs: inputs, specs: specs).iterations == 0)
        #expect(BroadcastPlan.nestedPlan(inputs: inputs, specs: specs).iterations == 0)
    }

    @Test func flatPlansJoinTheirResultsAsTheyAlwaysDid() {
        let single = BroadcastPlan.make(inputs: ["a": .one(.number(1))], specs: specs)
        guard case .one = single.assemble([[.integer(1)]], producedList: false) else { Issue.record("expected one"); return }
        guard case .list(let listed) = single.assemble([[.integer(1)]], producedList: true) else { Issue.record("expected a list"); return }
        #expect(listed.count == 1)
        let many = BroadcastPlan.make(inputs: ["a": .list([.number(1), .number(2)])], specs: specs)
        #expect(many.assemble([[.integer(1)], [.integer(2)]], producedList: false).outline == "[1,2]")
    }
}
