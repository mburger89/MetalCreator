import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Cull by Field (fields spec §3.3): Threshold and Probability, over a tree, keeping paths.
struct CullByFieldNodeTests {
    /// `count` placements along +X from the origin, 10 mm apart, then (in this order) a Partition into rows of `rows`, a Cull
    /// Pattern `mask`, and the Cull by Field with `settings`. Its field is x ÷ 10 unless `xField` is false, when `settings`
    /// should hold a number for "field".
    struct Rig {
        var h = Harness()
        let cull: Node

        init(count: Int = 4, rows: Int? = nil, mask: String? = nil, xField: Bool = true, _ settings: [SocketName: ConstantValue] = [:]) {
            let grid = h.add(GridPointsNode.self, [
                "countX": .integer(count), "countY": .integer(1), "spacingX": .number(10), "centred": .bool(false),
            ])
            let placements = h.add(PointsToPlacementsNode.self)
            cull = h.add(CullByFieldNode.self, settings)
            h.wire(grid, "points", to: placements, "points")
            var (source, socket): (Node, SocketName) = (placements, "placements")
            if let rows {
                let partition = h.add(PartitionNode.self, ["size": .integer(rows)])
                h.wire(source, socket, to: partition, "tree")
                (source, socket) = (partition, "tree")
            }
            if let mask {
                let before = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(mask)])
                h.wire(source, socket, to: before, "tree")
                (source, socket) = (before, "tree")
            }
            h.wire(source, socket, to: cull, "placements")
            if xField {
                let plane = h.add(PlaneNode.self, ["orientation": .integer(2)])  // YZ: its normal is +X
                let field = h.add(LinearGradientNode.self, ["length": .number(10)])
                h.wire(plane, "plane", to: field, "plane")
                h.wire(field, "field", to: cull, "field")
            }
        }

        func run() async throws -> EvaluationReport { try await h.run([cull]) }

        func kept() async throws -> [[Int]]? { try await run().positions(cull, "placements") }
    }

    /// Probability over `count` placements, a constant field `value`, seed `seed`.
    func probability(_ value: Double, seed: Int, count: Int = 10, rows: Int? = nil, mask: String? = nil) -> Rig {
        Rig(count: count, rows: rows, mask: mask, xField: false, ["mode": .integer(1), "seed": .integer(seed), "field": .number(value)])
    }

    // MARK: Threshold

    @Test func aboveKeepsWhatIsAtLeastTheLevel() async throws {
        let rig = Rig(count: 4, ["level": .number(1.5), "keep": .integer(0)])
        #expect(try await rig.kept() == [[2, 3]])
    }

    @Test func belowKeepsWhatIsAtMostTheLevel() async throws {
        let rig = Rig(count: 4, ["level": .number(1.5), "keep": .integer(1)])
        #expect(try await rig.kept() == [[0, 1]])
    }

    @Test func aValueExactlyOnTheLevelIsKeptEitherWay() async throws {
        let above = Rig(count: 4, ["level": .number(2), "keep": .integer(0)])
        let below = Rig(count: 4, ["level": .number(2), "keep": .integer(1)])
        #expect(try await above.kept() == [[2, 3]])
        #expect(try await below.kept() == [[0, 1, 2]])
    }

    @Test func theDefaultKeepsWhatIsAboveHalf() async throws {
        let rig = Rig(count: 4)
        #expect(try await rig.kept() == [[1, 2, 3]], "values 0, 1, 2, 3 against 0.5")
    }

    // MARK: Probability

    @Test func aFieldOfZeroKeepsNothingOneKeepsEverythingAndOutOfRangeIsHeld() async throws {
        for (value, count) in [(0.0, 0), (1.0, 10), (-3.0, 0), (7.0, 10)] {
            let rig = probability(value, seed: 5)
            let report = try await rig.run()
            #expect(report.tree(rig.cull, "placements")?.itemCount == count, "a field of \(value)")
            #expect(report.isOK(rig.cull), "a seed never warns")
        }
    }

    @Test func probabilityIsPinnedToTheSeededDraws() async throws {
        let rig = probability(0.5, seed: 1)
        let kept = try #require(try await rig.kept()?.first)
        let random = SeededRandom(seed: 1, stream: 0, purpose: .fieldCull)
        #expect(kept == (0..<10).filter { random.unit(at: $0) < 0.5 }, "draw k of the stream decides place k")
        // Seed 1's first ten draws are 0.74 0.84 0.33 0.90 0.34 0.47 0.92 0.07 0.62 0.30, worked out from the generator.
        #expect(kept == [2, 4, 5, 7, 9], "the draws are pinned: \(kept)")
    }

    @Test func theSameSeedGivesTheSameCullAndAnotherSeedAnother() async throws {
        #expect(try await probability(0.5, seed: 3, count: 40).kept() == probability(0.5, seed: 3, count: 40).kept())
        #expect(try await probability(0.5, seed: 3, count: 40).kept() != probability(0.5, seed: 4, count: 40).kept())
    }

    @Test func moreItemsAtTheEndChangeNoEarlierDecision() async throws {
        let short = try #require(try await probability(0.5, seed: 9, count: 12).kept()?.first)
        let long = try #require(try await probability(0.5, seed: 9, count: 20).kept()?.first)
        #expect(long.filter { $0 < 12 } == short)
    }

    @Test func eachBranchDrawsFromItsOwnStream() async throws {
        let rig = probability(0.5, seed: 7, count: 12, rows: 4)
        let kept = try #require(try await rig.kept())
        #expect(kept.count == 3)
        #expect(Set(kept).count > 1, "three branches do not repeat each other's draws: \(kept)")
        for (ordinal, positions) in kept.enumerated() {
            let random = SeededRandom(seed: 7, stream: ordinal, purpose: .fieldCull)
            #expect(positions == (0..<4).filter { random.unit(at: $0) < 0.5 })
        }
    }

    @Test func aCullBeforeChangesNoSurvivorsDraw() async throws {
        let everything = try #require(try await probability(0.5, seed: 42).kept()?.first)
        let survivors = try #require(try await probability(0.5, seed: 42, mask: "1 0").kept()?.first)  // "1 0" keeps the even places
        #expect(survivors == everything.filter { $0.isMultiple(of: 2) }, "an item decides as it would have, at its own index")
    }

    // MARK: shape and paths

    @Test func aTreeKeepsItsNestingWithCulledListsWhereItemsWent() async throws {
        let rig = Rig(count: 6, rows: 3, ["level": .number(2.5), "keep": .integer(0)])
        let report = try await rig.run()
        #expect(report.positions(rig.cull, "placements") == [[], [0, 1, 2]], "values 0 1 2 | 3 4 5")
        #expect(report.tree(rig.cull, "placements")?.depth == 2)
        #expect(report.tree(rig.cull, "placements")?.isCulled == true)
    }

    @Test func survivorsKeepTheIndicesTheyHad() async throws {
        let lower = Rig(count: 6, ["level": .number(2.5), "keep": .integer(1)])
        #expect(try await lower.kept() == [[0, 1, 2]])
        let upper = Rig(count: 6, ["level": .number(2.5), "keep": .integer(0)])
        let rest = try #require(try await upper.run().tree(upper.cull, "placements"))
        #expect(rest.leaves.first?.positions == [3, 4, 5], "{3}, {4} and {5}, not renumbered from 0")
        #expect(rest.isCulled)
    }

    @Test func aCulledListFromBeforeIsJudgedBySurvivorsAtTheirPlaces() async throws {
        let rig = Rig(count: 6, mask: "0 1", ["level": .number(2.5), "keep": .integer(0)])  // "0 1" keeps the places 1, 3 and 5
        #expect(try await rig.kept() == [[3, 5]], "values 1, 3 and 5 against 2.5")
    }

    // MARK: refusals

    @Test func aBadModeASideAndAMissingInputAreSaidPlainly() async throws {
        let bad = Rig(count: 3, ["mode": .integer(3)])
        #expect(try await bad.run().error(bad.cull) == "Choose Threshold or Probability for “mode”.")
        let badSide = Rig(count: 3, ["keep": .integer(2)])
        #expect(try await badSide.run().error(badSide.cull) == "Choose Above or Below for “keep”.")
        var open = Harness()
        let cull = open.add(CullByFieldNode.self)
        #expect(try await open.run([cull]).state(cull) == .idle("Connect or set “placements”."))
    }

    @Test func aListOfFieldsIsRefusedInWords() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self)
        let placements = h.add(PointsToPlacementsNode.self)
        let series = h.add(SeriesNode.self, ["count": .integer(3)])
        let cull = h.add(CullByFieldNode.self)
        h.wire(grid, "points", to: placements, "points")
        h.wire(placements, "placements", to: cull, "placements")
        h.wire(series, "values", to: cull, "field")
        #expect(try await h.run([cull]).error(cull) == Self.listRefusal)
    }

    /// The refusal runs before the node, so it names no socket: a list on `level` gets the same sentence as a list of fields.
    @Test func aListInAnotherInputIsRefusedInTheSameWords() async throws {
        var rig = Rig(count: 4)
        let series = rig.h.add(SeriesNode.self, ["count": .integer(3)])
        rig.h.wire(series, "values", to: rig.cull, "level")
        #expect(try await rig.run().error(rig.cull) == Self.listRefusal)
    }

    static let listRefusal = "Cull by Field takes single values, not lists: wire one value into each input, "
        + "or pick one out of the list first with List Item."
}
