import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Foundation
import Testing

/// Jitter (patterns spec §4): a random offset in each placement's own plane and a random turn about its normal, within limits,
/// from a seed. The pinned moves come straight from the generator (SplitMix64, `SeededRandomTests`, purpose `.jitter`): placement
/// `p` of a branch uses draws `3p`, `3p + 1` and `3p + 2` of the stream of its branch's ordinal.
struct JitterNodeTests {
    /// `count` placements in a row 20 mm apart facing `direction`, through Points to Placements, and a Jitter after them.
    struct Fixture {
        var h = Harness()
        let placements: Node
        let jitter: Node

        init(count: Int = 3, direction: Vector3 = .unitZ, rows: Int? = nil, _ settings: [SocketName: ConstantValue] = [:]) {
            let grid = h.add(GridPointsNode.self, ["countX": .integer(count), "countY": .integer(1), "spacingX": .number(20)])
            placements = h.add(PointsToPlacementsNode.self, ["direction": .vector(direction)])
            jitter = h.add(JitterNode.self, settings)
            h.wire(grid, "points", to: placements, "points")
            if let rows {
                let partition = h.add(PartitionNode.self, ["size": .integer(rows)])
                h.wire(placements, "placements", to: partition, "tree")
                h.wire(partition, "tree", to: jitter, "placements")
            } else {
                h.wire(placements, "placements", to: jitter, "placements")
            }
        }

        func planes(_ source: Node, _ socket: SocketName = "placements") async throws -> [Plane] {
            let report = try await h.run([source])
            return try #require(report.value(source, socket)?.planes)
        }
    }

    /// How far `plane` is from `original` along `original`'s own x and y axes, and how many degrees it is turned about its normal.
    func move(_ plane: Plane, from original: Plane) -> (x: Double, y: Double, along: Double, turn: Double) {
        let offset = plane.origin - original.origin
        let turn = atan2(plane.xAxis.dot(original.yAxis), plane.xAxis.dot(original.xAxis)) * 180 / .pi
        return (offset.dot(original.xAxis), offset.dot(original.yAxis), offset.dot(original.normal), turn)
    }

    // MARK: pinned moves

    @Test func seed42MovesThreePlacementsByPinnedAmounts() async throws {
        let f = Fixture(["distance": .number(2), "turn": .number(10), "seed": .integer(42)])
        let before = try await f.planes(f.placements)
        let after = try await f.planes(f.jitter)
        let moves = zip(after, before).map { move($0, from: $1) }
        let expected: [(Double, Double, Double)] = [
            (1.3832763664803966, -0.6613081950817091, 5.572337181192553),
            (1.0336785380656945, -0.029146096083390582, -0.640825595687553),
            (-1.105362466263014, 1.4331253961810904, 7.491161609836691),
        ]
        for (actual, wanted) in zip(moves, expected) {
            #expect(isClose(actual.x, wanted.0, relative: 1e-9) && isClose(actual.y, wanted.1, relative: 1e-9))
            #expect(isClose(actual.turn, wanted.2, relative: 1e-9))
            #expect(isClose(actual.along, 0, relative: 1e-9))
        }
    }

    @Test func anotherBranchDrawsFromItsOwnStream() async throws {
        let f = Fixture(count: 4, rows: 2, ["distance": .number(2), "turn": .number(0), "seed": .integer(42)])
        let report = try await f.h.run([f.jitter])
        let tree = try #require(report.tree(f.jitter, "placements"))
        let first = try #require(tree.leaves[1].items.first)
        guard case .plane(let plane) = first else { throw NodeError.invalidValue("not a plane") }
        let original = try await f.planes(f.placements)[2]
        let stream1 = SeededRandom(seed: 42, stream: 1, purpose: .jitter)
        let radius = 2 * stream1.unit(at: 0).squareRoot()
        #expect(isClose((plane.origin - original.origin).length, radius, relative: 1e-9), "branch 1 uses stream 1")
    }

    // MARK: limits

    @Test func everyMoveStaysInsideItsPlaneAndWithinTheLimits() async throws {
        let f = Fixture(count: 200, direction: Vector3(1, 1, 0), ["distance": .number(3), "turn": .number(25), "seed": .integer(5)])
        let before = try await f.planes(f.placements)
        let after = try await f.planes(f.jitter)
        #expect(after.count == 200)
        for (shaken, original) in zip(after, before) {
            let m = move(shaken, from: original)
            #expect(abs(m.along) < 1e-9, "never out of its plane")
            #expect((m.x * m.x + m.y * m.y).squareRoot() <= 3 + 1e-9)
            #expect(abs(m.turn) <= 25 + 1e-9)
            #expect(isClose(shaken.normal, original.normal))
            #expect(abs(shaken.xAxis.length - 1) < 1e-9 && abs(shaken.xAxis.dot(shaken.normal)) < 1e-9, "still a clean frame")
        }
        let moves = zip(after, before).map { move($0, from: $1) }
        #expect(moves.contains { $0.x > 1 } && moves.contains { $0.x < -1 }, "it moves both ways")
        #expect(moves.contains { $0.turn > 10 } && moves.contains { $0.turn < -10 }, "it turns both ways")
    }

    @Test func noDistanceAndNoTurnLeaveTheSamePlacements() async throws {
        let f = Fixture(["distance": .number(0), "turn": .number(0), "seed": .integer(9)])
        let before = try await f.planes(f.placements)
        let after = try await f.planes(f.jitter)
        for (a, b) in zip(after, before) {
            #expect(isClose(a.origin, b.origin) && isClose(a.xAxis, b.xAxis) && isClose(a.normal, b.normal))
        }
    }

    @Test func onlyTheTurnOrOnlyTheDistanceCanBeUsed() async throws {
        let turnOnly = Fixture(["distance": .number(0), "turn": .number(30), "seed": .integer(1)])
        let before = try await turnOnly.planes(turnOnly.placements)
        let turned = try await turnOnly.planes(turnOnly.jitter)
        #expect(zip(turned, before).allSatisfy { isClose($0.origin, $1.origin) })
        #expect(zip(turned, before).contains { abs(move($0, from: $1).turn) > 1 })
        let moveOnly = Fixture(["distance": .number(2), "turn": .number(0), "seed": .integer(1)])
        let moved = try await moveOnly.planes(moveOnly.jitter)
        #expect(zip(moved, before).allSatisfy { isClose($0.xAxis, $1.xAxis) })
    }

    // MARK: seeds

    @Test func theSameSeedGivesTheSamePlacementsEveryTime() async throws {
        let first = Fixture(count: 30, ["seed": .integer(77)])
        let second = Fixture(count: 30, ["seed": .integer(77)])
        #expect(try await first.planes(first.jitter) == second.planes(second.jitter))
    }

    @Test func anotherSeedMovesThemElsewhereAndNeverWarns() async throws {
        let first = Fixture(["seed": .integer(1)])
        let second = Fixture(["seed": .integer(2)])
        #expect(try await first.planes(first.jitter) != second.planes(second.jitter))
        let report = try await second.h.run([second.jitter])
        #expect(report.isOK(second.jitter))
    }

    @Test func addingPlacementsDoesNotMoveTheEarlierOnes() async throws {
        let few = Fixture(count: 3, ["seed": .integer(8)])
        let many = Fixture(count: 6, ["seed": .integer(8)])
        // The grid is centred, so the rows start in different places; what must match is how far each placement moved.
        let fewMoves = zip(try await few.planes(few.jitter), try await few.planes(few.placements)).map { move($0, from: $1) }
        let manyMoves = zip(try await many.planes(many.jitter), try await many.planes(many.placements)).map { move($0, from: $1) }
        for (a, b) in zip(fewMoves, manyMoves.prefix(3)) {
            #expect(isClose(a.x, b.x) && isClose(a.y, b.y) && isClose(a.turn, b.turn))
        }
    }

    // MARK: shape

    @Test func aCulledInputStaysCulledAndTheSurvivorsMoveAsTheyWouldHave() async throws {
        let plain = Fixture(count: 3, ["seed": .integer(42)])
        let everyone = try await plain.planes(plain.jitter)
        var h = plain.h
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let jitter = h.add(JitterNode.self, ["seed": .integer(42)])
        h.wire(plain.placements, "placements", to: cull, "tree")
        h.wire(cull, "tree", to: jitter, "placements")
        let report = try await h.run([jitter])
        #expect(report.positions(jitter, "placements") == [[0, 2]])
        let survivors = try #require(report.value(jitter, "placements")?.planes)
        #expect(survivors == [everyone[0], everyone[2]], "the draws follow the indices, not the order")
    }

    @Test func aTreeKeepsItsBranches() async throws {
        let f = Fixture(count: 6, rows: 3)
        let report = try await f.h.run([f.jitter])
        #expect(report.tree(f.jitter, "placements")?.leaves.map(\.items.count) == [3, 3])
    }

    // MARK: use

    @Test func jitteredPlacementsPlaceCopiesWhereTheyAre() async throws {
        var f = Fixture(count: 2, ["distance": .number(2), "turn": .number(0), "seed": .integer(3)])
        let tool = f.h.box(4, 4, 4)
        let place = f.h.add(PlaceNode.self)
        f.h.wire(tool, "solid", to: place, "tool")
        f.h.wire(f.jitter, "placements", to: place, "placements")
        let report = try await f.h.run([place])
        let copies = try #require(report.value(place, "solids")?.solids)
        let planes = try await f.planes(f.jitter)
        #expect(copies.count == 2)
        for (copy, plane) in zip(copies, planes) {
            let centre = (copy.bounds.min + copy.bounds.max) * 0.5
            #expect(isClose(centre.x, plane.origin.x) && isClose(centre.y, plane.origin.y))
        }
    }

    // MARK: refusals

    @Test func badLimitsAreRefusedInPlainWords() async throws {
        let distance = Fixture(["distance": .number(-1)])
        #expect(try await distance.h.run([distance.jitter]).error(distance.jitter) == "“distance” can't be negative.")
        let turn = Fixture(["turn": .number(-1)])
        #expect(try await turn.h.run([turn.jitter]).error(turn.jitter) == "“turn” can't be negative.")
    }
}
