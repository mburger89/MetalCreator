import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Random Reduce (patterns spec §4): drop N or a fraction, per branch or overall, always from a seed. The pinned results
/// were worked out straight from the generator (SplitMix64, `SeededRandomTests`, purpose `.reduce`): each item's key is the draw at
/// its index in the stream of its branch's ordinal, and the smallest keys go.
struct RandomReduceNodeTests {
    func reduce(_ settings: [SocketName: ConstantValue], count: Int,
                rows: Int? = nil) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let reduce = h.add(RandomReduceNode.self, settings)
        h.wire(source, to: reduce, "tree")
        return (try await h.run([reduce]), reduce)
    }

    // MARK: pinned results

    @Test func seed42DropsThreeOfTenAtIndices1And2And5() async throws {
        let (report, node) = try await reduce(["count": .integer(3), "seed": .integer(42)], count: 10)
        #expect(report.positions(node) == [[0, 3, 4, 6, 7, 8, 9]])
        #expect(report.value(node, "tree")?.outline == "[0,3,4,6,7,8,9]")
        #expect(report.isOK(node), "a seed never warns")
    }

    @Test func perBranchEveryBranchLosesItsOwnItem() async throws {
        let (report, node) = try await reduce(["scope": .integer(0), "seed": .integer(7)], count: 12, rows: 4)
        #expect(report.positions(node) == [[0, 1, 2], [1, 2, 3], [0, 2, 3]])
        let (other, otherNode) = try await reduce(["scope": .integer(0), "seed": .integer(8)], count: 12, rows: 4)
        #expect(other.positions(otherNode) == [[0, 1, 3], [1, 2, 3], [0, 2, 3]])
    }

    @Test func overallTheWholeTreeLosesThreeWhereverTheyAre() async throws {
        let (report, node) = try await reduce(["count": .integer(3), "scope": .integer(1), "seed": .integer(7)], count: 12, rows: 4)
        #expect(report.positions(node) == [[1, 2], [0, 1, 2, 3], [0, 2, 3]])
    }

    @Test func theDefaultDropsOneItemFromTheWholeTreeNotOnePerBranch() async throws {
        let (report, node) = try await reduce([:], count: 12, rows: 4)
        #expect(report.tree(node)?.itemCount == 11)
        let (ones, onesNode) = try await reduce([:], count: 6, rows: 1)
        #expect(ones.tree(onesNode)?.itemCount == 5, "branches of one item each are not emptied (User decision U16)")
    }

    @Test func theScopeStartsOnOverall() {
        #expect(RandomReduceNode.inputs.first { $0.name == "scope" }?.defaultValue == .integer(1))
    }

    @Test func perBranchOnBranchesOfOneItemDropsEveryItemAsItSays() async throws {
        let (report, node) = try await reduce(["scope": .integer(0)], count: 6, rows: 1)
        #expect(report.tree(node)?.itemCount == 0, "one from each branch of one is all of them: choose Overall for such a tree")
    }

    // MARK: properties

    @Test func theSameSeedGivesTheSameResultEveryTime() async throws {
        let first = try await reduce(["count": .integer(4), "seed": .integer(99)], count: 20)
        let second = try await reduce(["count": .integer(4), "seed": .integer(99)], count: 20)
        #expect(first.report.positions(first.node) == second.report.positions(second.node))
    }

    @Test func anotherSeedDropsOtherItems() async throws {
        var seen = Set<[[Int]]>()
        for seed in 0..<8 {
            let (report, node) = try await reduce(["count": .integer(3), "seed": .integer(seed)], count: 20)
            seen.insert(try #require(report.positions(node)))
        }
        #expect(seen.count > 4, "eight seeds make more than four different choices")
    }

    @Test func aBiggerCountDropsWhatASmallerOneDidAndMore() async throws {
        let two = try await reduce(["count": .integer(2), "seed": .integer(42)], count: 10)
        let three = try await reduce(["count": .integer(3), "seed": .integer(42)], count: 10)
        let keptTwo = Set(try #require(two.report.positions(two.node)?.first))
        let keptThree = Set(try #require(three.report.positions(three.node)?.first))
        #expect(keptThree.isSubset(of: keptTwo))
        #expect(keptTwo.subtracting(keptThree).count == 1)
    }

    @Test func moreItemsAtTheEndNeverChangeWhichEarlierOneIsLowest() async throws {
        let short = try await reduce(["seed": .integer(42)], count: 8)
        let long = try await reduce(["seed": .integer(42)], count: 10)
        let droppedShort = Set(0..<8).subtracting(try #require(short.report.positions(short.node)?.first))
        let droppedLong = Set(0..<10).subtracting(try #require(long.report.positions(long.node)?.first))
        #expect(droppedShort == [5] && droppedLong == [5])
    }

    // MARK: amounts

    @Test func aFractionIsRoundedToTheNearestWholeItemHalvesUp() async throws {
        for (fraction, dropped) in [(0.0, 0), (0.25, 2), (0.5, 3), (0.75, 5), (1.0, 6)] {
            let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(fraction)], count: 6)
            #expect(report.tree(node)?.itemCount == 6 - dropped, "\(fraction) of 6 drops \(dropped)")
        }
    }

    @Test func aFractionPerBranchTakesThatFractionOfEachBranch() async throws {
        let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(0.5), "scope": .integer(0)], count: 12, rows: 4)
        #expect(report.positions(node)?.map(\.count) == [2, 2, 2])
    }

    @Test func aCountLargerThanTheBranchDropsItAllWithoutAWarning() async throws {
        let (report, node) = try await reduce(["count": .integer(9), "scope": .integer(0)], count: 6, rows: 3)
        #expect(report.positions(node) == [[], []])
        #expect(report.isOK(node))
    }

    @Test func dropNothingChangesNothingAndAPlainListStaysPlain() async throws {
        let (report, node) = try await reduce(["count": .integer(0)], count: 5)
        #expect(report.value(node, "tree")?.isList == true)
    }

    // MARK: paths

    @Test func itWorksOnWhatIsLeftAfterAnotherCullAndKeepsItsPaths() async throws {
        var h = Harness()
        let source = h.source(count: 10)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])  // {0}, {2}, {4}, {6}, {8}
        let reduce = h.add(RandomReduceNode.self, ["count": .integer(2), "seed": .integer(3)])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: reduce, "tree")
        let report = try await h.run([reduce])
        let kept = try #require(report.positions(reduce)?.first)
        #expect(kept.count == 3)
        #expect(Set(kept).isSubset(of: [0, 2, 4, 6, 8]), "only paths that were there, none renumbered")
    }

    @Test func anEmptyBranchStaysAndIsNotAnError() async throws {
        var h = Harness()
        let source = h.source(count: 4, rows: 2)
        let none = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("0")])
        let reduce = h.add(RandomReduceNode.self)
        h.wire(source, to: none, "tree")
        h.wire(none, "tree", to: reduce, "tree")
        let report = try await h.run([reduce])
        #expect(report.isOK(reduce))
        #expect(report.positions(reduce) == [[], []])
    }

    // MARK: refusals

    @Test func badAmountsAreRefusedInPlainWords() async throws {
        let (negative, negativeNode) = try await reduce(["count": .integer(-1)], count: 4)
        #expect(negative.error(negativeNode) == "“count” can't be negative.")
        for fraction in [-0.1, 1.5] {
            let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(fraction)], count: 4)
            #expect(report.error(node) == "“fraction” must be between 0 and 1: 0 drops nothing and 1 drops everything.")
        }
        let (choice, choiceNode) = try await reduce(["scope": .integer(5)], count: 4)
        #expect(choice.error(choiceNode) == "Choose Per branch or Overall for “scope”.")
    }
}
