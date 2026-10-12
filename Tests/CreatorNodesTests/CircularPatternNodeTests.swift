import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing

/// Circular Pattern (patterns spec §3): placements on a circle or several, one branch per ring.
struct CircularPatternNodeTests {
    func rings(_ settings: [SocketName: ConstantValue]) async throws -> [[Plane]] {
        var h = Harness()
        let node = h.add(CircularPatternNode.self, settings)
        let report = try await h.run([node])
        let tree = try #require(report.value(node, "placements")?.asTree, "\(String(describing: report.state(node)))")
        return tree.leaves.map { leaf in leaf.items.compactMap { if case .plane(let plane) = $0 { plane } else { nil } } }
    }

    func error(_ settings: [SocketName: ConstantValue]) async throws -> String? {
        var h = Harness()
        let node = h.add(CircularPatternNode.self, settings)
        return try await h.run([node]).error(node)
    }

    @Test func fourPlacementsOnAFullCircleAreEvenAndTheFirstIsNotRepeated() async throws {
        let ring = try #require(try await rings(["count": .integer(4), "radius": .number(10), "centre": .vector(Vector3(1, 2, 3))]).first)
        let expected = [Vector3(11, 2, 3), Vector3(1, 12, 3), Vector3(-9, 2, 3), Vector3(1, -8, 3)]
        #expect(zip(ring.map(\.origin), expected).allSatisfy { isClose($0, $1) })
        #expect(ring.allSatisfy { $0.normal == .unitZ })
    }

    @Test func rotatingPointsEachXAxisOutwardsAndNotRotatingKeepsThemAlike() async throws {
        let turning = try #require(try await rings(["count": .integer(4)]).first)
        #expect(zip(turning.map(\.xAxis), [Vector3.unitX, .unitY, -.unitX, -.unitY]).allSatisfy { isClose($0, $1) })
        let still = try #require(try await rings(["count": .integer(4), "rotate": .bool(false)]).first)
        #expect(still.allSatisfy { isClose($0.xAxis, .unitX) })
    }

    @Test func aPartialSweepPutsTheLastPlacementAtTheEndOfTheSweep() async throws {
        let ring = try #require(try await rings(["count": .integer(4), "radius": .number(10), "sweep": .number(90)]).first)
        let angles = ring.map { atan2($0.origin.y, $0.origin.x) * 180 / .pi }
        #expect(zip(angles, [0, 30, 60, 90]).allSatisfy { isClose($0, $1) })
    }

    @Test func aSinglePlacementOnAPartialSweepStaysAtTheStart() async throws {
        let ring = try #require(try await rings(["count": .integer(1), "sweep": .number(90), "startAngle": .number(90)]).first)
        #expect(isClose(ring[0].origin, Vector3(0, 20, 0)))
    }

    @Test func aStartAngleTurnsTheWholeRing() async throws {
        let ring = try #require(try await rings(["count": .integer(4), "radius": .number(10), "startAngle": .number(45)]).first)
        #expect(isClose(ring[0].origin, Vector3(10 / 2.0.squareRoot(), 10 / 2.0.squareRoot(), 0)))
    }

    @Test func aNegativeSweepGoesClockwise() async throws {
        let ring = try #require(try await rings(["count": .integer(2), "radius": .number(10), "sweep": .number(-90)]).first)
        #expect(isClose(ring[1].origin, Vector3(0, -10, 0)))
    }

    @Test func ringsStepOutwardAndEachGetsTheCountStepMore() async throws {
        let rings = try await rings(["rings": .integer(3), "radius": .number(10), "radiusStep": .number(5), "count": .integer(6),
                                     "countStep": .integer(2),
        ])
        #expect(rings.map(\.count) == [6, 8, 10])
        #expect(zip(rings.map { $0[0].origin.length }, [10.0, 15, 20]).allSatisfy { isClose($0, $1) })
    }

    @Test func theRingsAreBranchesInOrder() async throws {
        var h = Harness()
        let node = h.add(CircularPatternNode.self, ["rings": .integer(3)])
        let tree = try #require(try await h.run([node]).value(node, "placements")?.asTree)
        #expect(tree.depth == 2 && tree.leaves.map(\.path.indices) == [[0], [1], [2]])
    }

    @Test func oneRingIsStillATreeSoAddingARingRenamesNoPath() async throws {
        var h = Harness()
        let node = h.add(CircularPatternNode.self)
        #expect(try await h.run([node]).value(node, "placements")?.depth == 2)
    }

    @Test func anotherAxisTurnsTheRingAboutIt() async throws {
        let ring = try #require(try await rings(["axis": .vector(.unitX), "count": .integer(4), "radius": .number(10)]).first)
        // Plane from Face's x axis for a normal of +X is world Y; the ring then runs from Y towards Z.
        let expected = [Vector3(0, 10, 0), Vector3(0, 0, 10), Vector3(0, -10, 0), Vector3(0, 0, -10)]
        #expect(zip(ring.map(\.origin), expected).allSatisfy { isClose($0, $1) })
        #expect(ring.allSatisfy { $0.normal == .unitX })
    }

    @Test func noRingsAndNoCountsMakeAnEmptyTree() async throws {
        #expect(try await rings(["rings": .integer(0)]).isEmpty)
        #expect(try await rings(["count": .integer(0)]).map(\.count) == [0])
        #expect(try await rings(["rings": .integer(2), "count": .integer(2), "countStep": .integer(-2)]).map(\.count) == [2, 0])
    }

    @Test(arguments: [
        (["count": .integer(-1)], "“count” can't be negative."),
        (["axis": .vector(.zero)], "“axis” can't be zero."),
        (["rings": .integer(-1)], "“rings” can't be negative."),
        (["rings": .integer(3), "radius": .number(1), "radiusStep": .number(-1)],
         "Ring 2 would have a negative radius: raise “radius” or lower “radiusStep”."),
        (["rings": .integer(3), "count": .integer(1_000)], "Patterns are limited to 2,000 instances."),
        (["rings": .integer(3), "count": .integer(1), "countStep": .integer(-1)],
         "Ring 2 would have a negative count: raise “count” or lower “countStep”."),
        (["rings": .integer(3), "countStep": .integer(Int.max)], "Patterns are limited to 2,000 instances."),
        (["count": .integer(2_001)], "Patterns are limited to 2,000 instances."),
        (["rings": .integer(Int.max)], "Patterns are limited to 2,000 instances."),
    ] as [([SocketName: ConstantValue], String)])
    func aBadInputIsRefusedInPlainWords(settings: [SocketName: ConstantValue], message: String) async throws {
        #expect(try await error(settings) == message)
    }
}
