import CreatorGeometry
import Testing
@testable import CreatorNodes

/// Variable-radius Poisson-disk sampling (fields spec §3.3, §8: "no two points closer than minSpacing; density follows the
/// field; same inputs, same points").
struct PoissonScatterTests {
    static func box(_ width: Double, _ height: Double) -> FaceRegion {
        FaceRegion(loops: [[Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)]])
    }

    static func scatter(_ region: FaceRegion, margin: Double = 0, min: Double = 5, max: Double = 5, seed: Int = 1,
                        ceiling: Int = 8_000, spacing: @escaping @Sendable (Vector2) -> Double = { _ in 5 }) async throws
        -> PoissonScatter.Outcome {
        try await PoissonScatter(region: region, margin: margin, minSpacing: min, maxSpacing: max, seed: seed, ceiling: ceiling)
            .scatter { points in points.map(spacing) }
    }

    static func nearestPair(_ points: [Vector2]) -> Double {
        var nearest = Double.infinity
        for (index, a) in points.enumerated() {
            for b in points[(index + 1)...] { nearest = Swift.min(nearest, (a - b).length) }
        }
        return nearest
    }

    @Test func thePurposeAndItsFirstDrawArePinned() {
        #expect(SeededRandom.Purpose.scatter.rawValue == 0x5363_6174_7472_5F31)
        #expect(SeededRandom(seed: 5, purpose: .scatter).value(at: 0) == 0xC09C_3D16_F529_5801)
        #expect(SeededRandom(seed: 5, stream: 3, purpose: .scatter).value(at: 0) == 0xD7DC_9517_E196_AFB9)
        #expect(SeededRandom(seed: 5, purpose: .scatter).value(at: 0) != SeededRandom(seed: 5, purpose: .fieldCull).value(at: 0))
    }

    @Test func noTwoPointsAreCloserThanTheMinimumAndEveryPointIsInsideTheMargin() async throws {
        let region = Self.box(60, 40)
        let outcome = try await Self.scatter(region, margin: 3, min: 5, max: 5)
        #expect(outcome.points.count >= 40, "a 54 × 34 area at spacing 5 holds dozens: \(outcome.points.count)")
        #expect(Self.nearestPair(outcome.points) >= 5 - 1e-9)
        #expect(outcome.points.allSatisfy { region.allows($0, margin: 3) })
        #expect(!outcome.reachedCeiling)
    }

    @Test func aHoleAndItsMarginStayEmpty() async throws {
        let hole = [Vector2(20, 10), Vector2(40, 10), Vector2(40, 30), Vector2(20, 30)]
        let region = FaceRegion(loops: [[Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)], hole])
        let outcome = try await Self.scatter(region, margin: 2)
        #expect(outcome.points.count > 10)
        #expect(outcome.points.allSatisfy { !(18...42).contains($0.x) || !(8...32).contains($0.y) })
    }

    @Test func islandsTheMarginCutOffAreAllFilled() async throws {
        let left = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)]
        let right = [Vector2(60, 0), Vector2(80, 0), Vector2(80, 20), Vector2(60, 20)]
        let outcome = try await Self.scatter(FaceRegion(loops: [left, right]), min: 5, max: 5)
        #expect(outcome.points.filter { $0.x < 40 }.count >= 8 && outcome.points.filter { $0.x > 40 }.count >= 8)
        #expect(Self.nearestPair(outcome.points) >= 5 - 1e-9)
    }

    @Test func sameInputsGiveTheSamePointsAndAnotherSeedGivesOthers() async throws {
        let region = Self.box(60, 40)
        let first = try await Self.scatter(region, seed: 7)
        let again = try await Self.scatter(region, seed: 7)
        let other = try await Self.scatter(region, seed: 8)
        #expect(first == again)
        #expect(first.points != other.points)
    }

    @Test func densityFollowsTheSpacing() async throws {
        // Spacing 4 in the left half of a 100 × 40 box and 10 in the right: about (10 / 4)² = 6 times the points on the left.
        let outcome = try await Self.scatter(Self.box(100, 40), min: 4, max: 10) { $0.x < 50 ? 4 : 10 }
        let left = outcome.points.filter { $0.x < 50 }.count
        let right = outcome.points.count - left
        #expect(right > 0 && left > 3 * right, "left \(left), right \(right)")
        #expect(Self.nearestPair(outcome.points) >= 4 - 1e-9)
    }

    @Test func aPointIsAtLeastItsOwnSpacingFromEveryOneBeforeIt() async throws {
        // The spacing grows along x: each point keeps its own spacing's distance from the points placed before it.
        let spacing: @Sendable (Vector2) -> Double = { 4 + $0.x / 20 }
        let outcome = try await Self.scatter(Self.box(100, 40), min: 4, max: 9, spacing: spacing)
        for (index, point) in outcome.points.enumerated() {
            let nearest = outcome.points[..<index].map { ($0 - point).length }.min() ?? .infinity
            #expect(nearest >= spacing(point) - 1e-9, "point \(index) at \(point)")
        }
    }

    @Test func theSpacingIsAskedForInBatchesNeverPointByPoint() async throws {
        let log = BatchLog()
        let outcome = try await PoissonScatter(region: Self.box(60, 40), margin: 0, minSpacing: 5, maxSpacing: 5, seed: 1, ceiling: 8_000)
            .scatter { points in
                await log.record(points.count)
                return points.map { _ in 5 }
            }
        let calls = await log.sizes
        #expect(calls.count < outcome.points.count, "one call per round of candidates, fewer calls than points")
        #expect(calls.max() ?? 0 > 1)
    }

    @Test func itStopsOnceMoreThanTheCeilingExist() async throws {
        let outcome = try await Self.scatter(Self.box(200, 200), min: 2, max: 2, ceiling: 100) { _ in 2 }
        #expect(outcome.reachedCeiling && outcome.points.count == 101)
    }

    @Test func aRegionTheMarginEatsGivesNoPoints() async throws {
        let outcome = try await Self.scatter(Self.box(10, 10), margin: 6)
        #expect(outcome.points.isEmpty && !outcome.reachedCeiling)
    }

    @Test func aCancelledScatterStopsWithCancellationError() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Self.scatter(Self.box(60, 40))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// Collects the sizes of the batches the sampler was asked for.
actor BatchLog {
    private(set) var sizes: [Int] = []

    func record(_ count: Int) {
        sizes.append(count)
    }
}
