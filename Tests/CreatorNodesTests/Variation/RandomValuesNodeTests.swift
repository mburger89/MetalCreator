import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Random Values (patterns spec §4): per-instance reals or whole numbers in a range, in the shape of a tree or a count, from a
/// seed. The pinned numbers come straight from the generator (SplitMix64, `SeededRandomTests`, purpose `.values`): the item at
/// index `i` of a branch with ordinal `n` gets draw `i` of stream `n`.
struct RandomValuesNodeTests {
    func run(_ settings: [SocketName: ConstantValue], shape: Int? = nil, rows: Int? = nil,
             culling pattern: String? = nil) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let node = h.add(RandomValuesNode.self, settings)
        if let shape {
            var source = h.source(count: shape, rows: rows)
            if let pattern {
                let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(pattern)])
                h.wire(source, to: cull, "tree")
                source = TreeSource(node: cull, socket: "tree")
            }
            h.wire(source, to: node, "shape")
        }
        return (try await h.run([node]), node)
    }

    func close(_ actual: [Double]?, _ expected: [Double]) -> Bool {
        guard let actual, actual.count == expected.count else { return false }
        return zip(actual, expected).allSatisfy { isClose($0, $1, relative: 1e-12) }
    }

    // MARK: pinned numbers

    @Test func seed42GivesPinnedRealsFromZeroToOne() async throws {
        let (report, node) = try await run(["count": .integer(4), "seed": .integer(42)])
        #expect(close(report.value(node, "values")?.numbers,
                      [0.975521979100528, 0.6467038549042005, 0.1577190784555612, 0.32818821561135025]))
        #expect(report.isOK(node), "a seed never warns")
    }

    @Test func realsAreScaledIntoTheRange() async throws {
        let (report, node) = try await run(["count": .integer(4), "min": .number(10), "max": .number(20), "seed": .integer(42)])
        #expect(close(report.value(node, "values")?.numbers,
                      [19.75521979100528, 16.467038549042005, 11.577190784555611, 13.281882156113502]))
    }

    @Test func wholeNumbersAreInTheRangeAndPinned() async throws {
        let (report, node) = try await run(["count": .integer(4), "min": .number(0), "max": .number(9), "seed": .integer(42)])
        #expect(report.value(node, "integers")?.integers == [9, 6, 1, 3])
        let (dice, diceNode) = try await run(["count": .integer(4), "min": .number(1), "max": .number(6), "seed": .integer(42)])
        #expect(dice.value(diceNode, "integers")?.integers == [6, 4, 1, 2], "1 to 6 is the draws 5, 3, 0, 1 plus 1")
    }

    @Test func aNegativeSeedIsAValidSeed() async throws {
        let (report, node) = try await run(["count": .integer(3), "seed": .integer(-5)])
        #expect(close(report.value(node, "values")?.numbers, [0.8078499237740443, 0.031857563103228737, 0.5850738692585525]))
    }

    @Test func eachBranchDrawsFromItsOwnStream() async throws {
        let (report, node) = try await run(["min": .number(0), "max": .number(9), "seed": .integer(42)], shape: 4, rows: 2)
        // Branch 0 uses stream 0 (9, 6) and branch 1 stream 1 (5, 2).
        #expect(report.value(node, "integers")?.outline == "[[9,6],[5,2]]")
    }

    // MARK: independence

    @Test func theFirstNumbersDoNotDependOnHowManyThereAre() async throws {
        let few = try await run(["count": .integer(4), "seed": .integer(11)])
        let many = try await run(["count": .integer(9), "seed": .integer(11)])
        let manyNumbers = try #require(many.report.value(many.node, "values")?.numbers)
        #expect(close(few.report.value(few.node, "values")?.numbers, Array(manyNumbers.prefix(4))))
    }

    @Test func anotherSeedGivesOtherNumbers() async throws {
        let first = try await run(["count": .integer(5), "seed": .integer(1)])
        let second = try await run(["count": .integer(5), "seed": .integer(2)])
        #expect(first.report.value(first.node, "values")?.numbers != second.report.value(second.node, "values")?.numbers)
    }

    @Test func theSameSeedGivesTheSameNumbersEveryTime() async throws {
        let first = try await run(["count": .integer(50), "seed": .integer(123)])
        let second = try await run(["count": .integer(50), "seed": .integer(123)])
        #expect(first.report.value(first.node, "values")?.numbers == second.report.value(second.node, "values")?.numbers)
    }

    // MARK: shape

    @Test func aWiredShapeSetsTheNestingAndCountIsIgnored() async throws {
        let (report, node) = try await run(["count": .integer(99)], shape: 7, rows: 3)
        #expect(report.tree(node, "values")?.dimensions == nil)
        #expect(report.value(node, "values")?.outline.hasPrefix("[[") == true)
        #expect(report.tree(node, "values")?.leaves.map(\.items.count) == [3, 3, 1])
    }

    @Test func aCulledShapeGetsNumbersAtThePathsItKeptAndTheOthersKeepTheirNumbers() async throws {
        let all = try await run(["seed": .integer(42)], shape: 6, rows: 3)
        let culled = try await run(["seed": .integer(42)], shape: 6, rows: 3, culling: "1 0")
        let allTree = try #require(all.report.tree(all.node, "values"))
        let culledTree = try #require(culled.report.tree(culled.node, "values"))
        #expect(culledTree.leaves.map(\.positions) == [[0, 2], [0, 2]], "the numbers sit at the paths that were kept")
        // The numbers at the kept paths are the ones the uncilled shape gives those paths.
        let wanted = allTree.leaves.flatMap { leaf in [0, 2].map { leaf.items[$0] } }
        #expect(culledTree.items.map(\.outlineText) == wanted.map(\.outlineText))
    }

    @Test func theNumbersFitStraightIntoASizeInput() async throws {
        var h = Harness()
        let random = h.add(RandomValuesNode.self, ["count": .integer(3), "min": .number(5), "max": .number(15), "seed": .integer(42)])
        let circle = h.add(CircleNode.self)
        h.wire(random, "values", to: circle, "diameter")
        let report = try await h.run([circle])
        #expect(report.value(circle, "profile")?.profiles?.count == 3, "three circles, one diameter each")
    }

    // MARK: range

    @Test func aRangeWithNoWholeNumberLeavesTheIntegersOutButStillGivesReals() async throws {
        let (report, node) = try await run(["count": .integer(3), "min": .number(0.2), "max": .number(0.8)])
        #expect(report.value(node, "values")?.numbers?.count == 3)
        #expect(report.value(node, "integers") == nil)
        #expect(report.isOK(node))
    }

    @Test func aSingleValuedRangeAlwaysGivesIt() async throws {
        let (report, node) = try await run(["count": .integer(3), "min": .number(4), "max": .number(4)])
        #expect(report.value(node, "values")?.numbers == [4, 4, 4])
        #expect(report.value(node, "integers")?.integers == [4, 4, 4])
    }

    @Test func negativeRangesWork() async throws {
        let (report, node) = try await run(["count": .integer(200), "min": .number(-3), "max": .number(3), "seed": .integer(9)])
        let whole = try #require(report.value(node, "integers")?.integers)
        #expect(whole.allSatisfy { (-3...3).contains($0) })
        #expect(Set(whole) == Set(-3...3), "every whole number from −3 to 3 turns up in 200 draws")
        #expect(try #require(report.value(node, "values")?.numbers).allSatisfy { (-3.0..<3.0).contains($0) })
    }

    // MARK: refusals

    @Test func badSettingsAreRefusedInPlainWords() async throws {
        let (backwards, backwardsNode) = try await run(["min": .number(5), "max": .number(1)])
        #expect(backwards.error(backwardsNode) == "“min” can't be more than “max”.")
        let (negative, negativeNode) = try await run(["count": .integer(-1)])
        #expect(negative.error(negativeNode) == "“count” can't be negative.")
        let (huge, hugeNode) = try await run(["count": .integer(100_001)])
        #expect(huge.error(hugeNode) == "Random Values makes at most 100,000 numbers.")
        let (infinite, infiniteNode) = try await run(["max": .number(.infinity)])
        #expect(infinite.error(infiniteNode) == "“min” and “max” must be numbers.")
    }

    @Test func zeroCountMakesAnEmptyList() async throws {
        let (report, node) = try await run(["count": .integer(0)])
        #expect(report.value(node, "values")?.items.isEmpty == true)
    }
}
