import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct DistanceBakerTests {
    static let ball: @Sendable (Vector3) -> Double = { $0.length - 10 }
    static let box = BoundingBox(min: Vector3(-10, -10, -10), max: Vector3(10, 10, 10))

    @Test func theBakeReproducesTheFunctionNearTheSurface() async throws {
        let result = try await DistanceBaker.bake(bounds: Self.box, spacing: 0.5, distance: Self.ball)
        let random = SeededRandom(seed: 3, stream: 1)
        var checked = 0
        for index in 0..<2000 {
            let point = Vector3(random.unit(at: 3 * index) * 24 - 12, random.unit(at: 3 * index + 1) * 24 - 12,
                                random.unit(at: 3 * index + 2) * 24 - 12)
            guard abs(Self.ball(point)) < 3 else { continue }
            checked += 1
            // Trilinear error of a ball of radius 10 at 0.5 mm spacing is about 0.5² / 80 = 0.003.
            #expect(abs(result.blocks.value(at: point) - Self.ball(point)) < 0.01, "at \(point)")
        }
        #expect(checked > 200)
    }

    @Test func onlyBlocksNearTheSurfaceAreStored() async throws {
        let result = try await DistanceBaker.bake(bounds: Self.box, spacing: 0.25, distance: Self.ball)
        let blocks = result.blocks
        let total = blocks.blockCounts.reduce(1, *)
        #expect(blocks.storedBlockCount > 0 && blocks.storedBlockCount < total / 2)
        // A far corner of the grid and the middle of the ball read a sign and a lower bound that is not above the truth.
        let far = blocks.bounds.max - Vector3(0.1, 0.1, 0.1)
        #expect(blocks.value(at: far) > 0 && blocks.value(at: far) <= Self.ball(far) + 1e-6)
        #expect(blocks.value(at: .zero) < 0 && blocks.value(at: .zero) >= Self.ball(.zero) - 1e-6)
        #expect(abs(abs(blocks.value(at: .zero)) - 10) < 4, "the bound is conservative but not absurd")
    }

    @Test func aBakeIsTheSameEveryTime() async throws {
        let first = try await DistanceBaker.bake(bounds: Self.box, spacing: 1, distance: Self.ball)
        let second = try await DistanceBaker.bake(bounds: Self.box, spacing: 1, distance: Self.ball)
        #expect(first.blocks.pool == second.blocks.pool && first.blocks.table == second.blocks.table)
        #expect(first.blocks.coarse == second.blocks.coarse)
    }

    @Test func aPartTooBigForTheBudgetIsBakedCoarser() async throws {
        let result = try await DistanceBaker.bake(bounds: Self.box, spacing: 0.25, gridLimit: 2000, storedLimit: 300,
                                                  distance: Self.ball)
        #expect(result.spacing > 0.25)
        #expect(result.blocks.blockCounts.reduce(1, *) <= 2000 && result.blocks.storedBlockCount <= 300)
        #expect(abs(result.blocks.value(at: Vector3(10, 0, 0))) < 0.5, "still a ball")
    }

    @Test func theLimitsAreTheSpecsBudgets() {
        #expect(DistanceBaker.maximumGridBlocks == 4_000_000 && DistanceBaker.maximumStoredBlocks == 40_000)
    }

    @Test func theSpacingFollowsTheTolerance() {
        #expect(abs(DistanceBaker.spacing(forTolerance: 0.01) - 0.4) < 1e-12)
        #expect(DistanceBaker.spacing(forTolerance: 0.04) > DistanceBaker.spacing(forTolerance: 0.01))
    }

    @Test func cancellingStopsTheBake() async {
        let task = Task { try await DistanceBaker.bake(bounds: Self.box, spacing: 0.25, distance: Self.ball) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
