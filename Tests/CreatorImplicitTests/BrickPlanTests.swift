import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The sparse octree (implicit spec §4.2, §7): it never prunes a brick the surface passes through, and it prunes most of the rest.
struct BrickPlanTests {
    /// Every voxel of the lattice that has a sign change among its eight corners, found by evaluating everything.
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

    @Test(arguments: [("sphere", 0.5), ("box", 0.7), ("smooth union", 0.5), ("graded offset", 0.6), ("baked", 0.8), ("isosurface", 0.6)])
    func everyCrossingVoxelIsInASurvivingBrick(_ name: String, _ resolution: Double) async throws {
        let solid = try #require(ImplicitFixtures.all.first { $0.name == name }?.solid)
        let plan = try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid))
        let kept = Set(plan.bricks.map { SIMD3<Int>(Int($0.x), Int($0.y), Int($0.z)) })
        let crossings = crossingVoxels(of: solid, plan: plan)
        #expect(!crossings.isEmpty && !plan.bricks.isEmpty)
        for voxel in crossings {
            let brick = SIMD3(voxel.x / BrickPlan.brickSize, voxel.y / BrickPlan.brickSize, voxel.z / BrickPlan.brickSize)
            #expect(kept.contains(brick), "\(name): voxel \(voxel) is in brick \(brick), which was pruned")
        }
    }

    @Test func aSphereNeedsAboutAsManyBricksAsItsSurfaceHas() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let plan = try await BrickPlan.build(for: solid, resolution: 0.2, using: CPUBatchEvaluator(solid))
        // Area 4π·10² = 1257 mm²; a brick is 1.6 mm across, so 491 bricks tile it flat, and a sphere cuts up to twice that.
        #expect(plan.bricks.count > 491 && plan.bricks.count < 1100)
        let dense = plan.brickCounts.reduce(1, *)
        #expect(plan.bricks.count < dense / 2, "prunes the inside and the outside: \(plan.bricks.count) of \(dense)")
        #expect(plan.evaluatedCells < dense, "and never evaluates the dense grid: \(plan.evaluatedCells)")
    }

    @Test func theBricksAreSortedAndInsideTheGrid() async throws {
        let solid = ImplicitFixtures.box
        let plan = try await BrickPlan.build(for: solid, resolution: 0.5, using: CPUBatchEvaluator(solid))
        let keys = plan.bricks.map { [$0.x, $0.y, $0.z] }
        #expect(keys == keys.sorted { $0.lexicographicallyPrecedes($1) })
        for brick in plan.bricks {
            #expect(Int(brick.x) < plan.brickCounts[0] && Int(brick.y) < plan.brickCounts[1] && Int(brick.z) < plan.brickCounts[2])
        }
        #expect(Set(keys).count == keys.count)
    }

    @Test func theGridIsTheBoundsPaddedByOneVoxel() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let plan = try await BrickPlan.build(for: solid, resolution: 0.5, using: CPUBatchEvaluator(solid))
        #expect(plan.origin == Vector3(-10.5, -10.5, -10.5))
        // 21 mm over 4 mm bricks.
        #expect(plan.brickCounts == [6, 6, 6])
    }

    @Test func aSolidWithNothingToMeshHasNoBricks() async throws {
        // Two shapes that don't meet: an intersection has an empty (point-sized) box and no crossing.
        let move = RigidMove(origin: Vector3(20, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let apart = ImplicitSolid.intersect([.sphere(radius: 3), .moved(.sphere(radius: 3), move)], blend: .constant(0))
        let plan = try await BrickPlan.build(for: apart, resolution: 0.5, using: CPUBatchEvaluator(apart))
        #expect(plan.bricks.isEmpty)
    }

    @Test func samplesAreNineCubedPerBrickAndSharedFacesAgree() async throws {
        let solid = ImplicitFixtures.cylinder
        let evaluator = CPUBatchEvaluator(solid)
        let plan = try await BrickPlan.build(for: solid, resolution: 0.5, using: evaluator)
        let samples = try await plan.samples(of: plan.bricks[...], using: evaluator)
        #expect(samples.count == plan.bricks.count * 729)
        // Two bricks side by side read the same values on the face they share.
        let index = Dictionary(uniqueKeysWithValues: plan.bricks.enumerated().map { (SIMD3<Int>(Int($1.x), Int($1.y), Int($1.z)), $0) })
        var compared = 0
        for (brick, number) in index {
            guard let next = index[brick &+ SIMD3(1, 0, 0)] else { continue }
            for z in 0...8 {
                for y in 0...8 {
                    #expect(samples[number * 729 + (z * 9 + y) * 9 + 8] == samples[next * 729 + (z * 9 + y) * 9])
                    compared += 1
                }
            }
        }
        #expect(compared > 0)
    }

    @Test func cancellingStopsThePlan() async {
        let solid = ImplicitFixtures.sphere
        let task = Task { try await BrickPlan.build(for: solid, resolution: 0.1, using: CPUBatchEvaluator(solid)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
