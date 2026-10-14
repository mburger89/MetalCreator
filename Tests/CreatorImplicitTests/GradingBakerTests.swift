import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorImplicit

struct GradingBakerTests {
    let kernel = FakeKernel()
    let tag = NodeTag(node: NodeID(), item: 0)
    let region = BoundingBox(min: Vector3(-15, -15, -5), max: Vector3(15, 15, 15))

    func cube() async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
    }

    @Test func aConstantNeedsNoBakingAndKeepsItsValue() async throws {
        let grading = try await GradingBaker.grading(for: .constant(2), over: region, kernel: kernel)
        #expect(grading == .constant(2) && grading.constantValue == 2)
    }

    @Test func aFieldWithoutKernelDistancesIsNotBaked() async throws {
        let field = Field.remap(.noise(seed: 1, scale: 6, octaves: 2), fromLow: 0, fromHigh: 1, toLow: 0.6, toHigh: 1.6, clamped: true)
        let grading = try await GradingBaker.grading(for: field, over: region, kernel: kernel)
        #expect(grading.baked.isEmpty && grading.range == 0.6...1.6 && grading.slope == field.slopeBound.value)
        #expect(grading.constantValue == nil)
    }

    @Test func aDistanceToASolidIsBakedAndReadBack() async throws {
        let solid = try await cube()
        let field = Field.distance(.kernel(.solid(solid)), signed: true)
        let grading = try await GradingBaker.grading(for: field, over: region, kernel: kernel)
        #expect(grading.baked.count == 1)
        let blocks = try #require(grading.blocks(for: DistanceTarget.solid(solid).identity, signed: true))
        #expect(grading.blocks(for: DistanceTarget.solid(solid).identity, signed: false) == nil)
        // The shell of a big ball, 1 mm thick, graded by the cube's distance: read through the evaluator.
        let graded = ImplicitSolid.offset(.sphere(radius: 20), distance: grading)
        for point in [Vector3(8, 0, 5), Vector3(0, 0, 11), Vector3(0, 12, 5)] {
            let expected = point.length - 20 - blocks.value(at: point)
            #expect(abs(graded.signedDistance(at: point) - expected) < 1e-9)
        }
        #expect(abs(blocks.value(at: Vector3(8, 0, 5)) - 3) < 0.2, "within the interpolation error of a 0.75 mm grid")
    }

    @Test func theRangeAndSlopeCoverWhatTheGridSees() async throws {
        let solid = try await cube()
        let field = Field.distance(.kernel(.solid(solid)), signed: true)
        let grading = try await GradingBaker.grading(for: field, over: region, kernel: kernel)
        // Signed distance over the region runs from −5 (the cube's middle) to the far corner: (15, 15, 15) is √(10² + 10² + 5²) = 15 away.
        #expect(grading.range.lowerBound <= -4.5 && grading.range.upperBound >= 14.5)
        #expect(grading.slope >= 1)
        #expect(grading.slope == field.slopeBound.value + max(0, grading.baked[0].blocks.lipschitz - 1))
    }

    @Test func aClampedDistanceHasItsClampAsRange() async throws {
        let solid = try await cube()
        let field = Field.clamp(.distance(.kernel(.solid(solid)), signed: false), low: 0, high: 4)
        let grading = try await GradingBaker.grading(for: field, over: region, kernel: kernel)
        #expect(grading.range == 0...4)
    }

    @Test func eachDistinctDistanceIsBakedOnce() async throws {
        let solid = try await cube()
        let near = Field.distance(.kernel(.solid(solid)), signed: true)
        let field = Field.add(near, .multiply(near, .distance(.kernel(.solid(solid)), signed: false)))
        let grading = try await GradingBaker.grading(for: field, over: region, kernel: kernel)
        #expect(grading.baked.count == 2, "signed and unsigned are two bakes")
    }

    /// Every voxel of the plan's lattice with a sign change among its eight corners, found by evaluating everything.
    func crossingVoxels(of solid: ImplicitSolid, plan: BrickPlan) -> [SIMD3<Int>] {
        let size = BrickPlan.brickSize
        let counts = plan.brickCounts.map { $0 * size + 1 }
        let evaluation = CPUEvaluation()
        var values = [Double](repeating: 0, count: counts[0] * counts[1] * counts[2])
        for k in 0..<counts[2] {
            for j in 0..<counts[1] {
                for i in 0..<counts[0] {
                    values[(k * counts[1] + j) * counts[0] + i] = evaluation.distance(solid, at: plan.point(i, j, k))
                }
            }
        }
        var found: [SIMD3<Int>] = []
        for k in 0..<counts[2] - 1 {
            for j in 0..<counts[1] - 1 {
                for i in 0..<counts[0] - 1 {
                    let corners = (0..<8).map { values[((k + $0 >> 2) * counts[1] + j + ($0 >> 1 & 1)) * counts[0] + i + ($0 & 1)] }
                    if corners.contains(where: { $0 < 0 }) && corners.contains(where: { $0 >= 0 }) { found.append(SIMD3(i, j, k)) }
                }
            }
        }
        return found
    }

    @Test func aCoarseBakedGradingNeverLetsBrickPlanPruneACrossedBrick() async throws {
        let solid = try await cube()
        // A wide region makes the 40-cell grid coarse (3 mm cells), so the trilinear slope of the baked distance can exceed 1.
        let wide = BoundingBox(min: Vector3(-60, -60, -60), max: Vector3(60, 60, 60))
        // Clamped, so the offset stays small enough to mesh at this resolution.
        let field = Field.clamp(.distance(.kernel(.solid(solid)), signed: true), low: 0, high: 2)
        let grading = try await GradingBaker.grading(for: field, over: wide, kernel: kernel)
        let lipschitz = try #require(grading.baked.first?.blocks.lipschitz)
        #expect(lipschitz > 1, "the grid is coarse enough to be steeper than the exact distance")
        #expect(abs(grading.slope - (field.slopeBound.value + lipschitz - 1)) < 1e-12)
        let thickness = try await GradingBaker.grading(
            for: .clamp(.distance(.kernel(.solid(solid)), signed: false), low: 0.5, high: 6), over: wide, kernel: kernel)
        // A ball offset by the cube's distance, and a shell whose wall is graded by it.
        let solids: [ImplicitSolid] = [
            .offset(.sphere(radius: 12), distance: grading),
            .shell(.sphere(radius: 12), thickness: thickness, side: .inward),
        ]
        for graded in solids {
            let plan = try await BrickPlan.build(for: graded, resolution: 0.6, using: CPUBatchEvaluator(graded))
            let kept = Set(plan.bricks.map { SIMD3<Int>(Int($0.x), Int($0.y), Int($0.z)) })
            let crossings = crossingVoxels(of: graded, plan: plan)
            #expect(!crossings.isEmpty && !plan.bricks.isEmpty)
            let size = BrickPlan.brickSize
            for voxel in crossings {
                let brick = SIMD3(voxel.x / size, voxel.y / size, voxel.z / size)
                #expect(kept.contains(brick), "voxel \(voxel) is in brick \(brick), which was pruned")
            }
        }
    }
}
