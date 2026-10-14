import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct MeshingBudgetTests {
    let solid = ImplicitSolid.sphere(radius: 10)

    @Test func theEstimateGrowsWithTheSquareOfTheFinerResolution() async throws {
        let evaluator = CPUBatchEvaluator(solid)
        let coarse = try await MeshingBudget.estimate(for: solid, resolution: 0.5, using: evaluator)
        let fine = try await MeshingBudget.estimate(for: solid, resolution: 0.25, using: evaluator)
        #expect(coarse > 0)
        // Twice as fine is four times the surface voxels (the coarse pass is the same, so the ratio is exactly the scale).
        #expect(abs(Double(fine) / Double(coarse) - 4) < 0.2, "ratio \(Double(fine) / Double(coarse))")
    }

    @Test func theLimitIsHalfOfPhysicalMemory() {
        #expect(MeshingBudget(physicalMemory: 16_000_000_000).limit == 8_000_000_000)
    }

    @Test func aJobWithinTheLimitPasses() async throws {
        try await MeshingBudget(physicalMemory: 64_000_000_000).check(solid, resolution: 0.5, using: CPUBatchEvaluator(solid))
    }

    @Test func aJobOverTheLimitIsRefusedWithAWayOut() async throws {
        let budget = MeshingBudget(physicalMemory: 2_000_000)
        let evaluator = CPUBatchEvaluator(solid)
        let bytes = try await MeshingBudget.estimate(for: solid, resolution: 0.1, using: evaluator)
        do {
            try await budget.check(solid, resolution: 0.1, using: evaluator)
            Issue.record("the job should have been refused")
        } catch let error as ImplicitMeshingError {
            guard case .tooBig(let reported, let resolution, let suggestion) = error else { Issue.record("wrong error"); return }
            #expect(reported == bytes && resolution == 0.1)
            // The suggestion makes the job fit: bytes follow 1 / resolution².
            #expect(suggestion > 0.1)
            let fits = Double(bytes) * (0.1 / suggestion) * (0.1 / suggestion)
            #expect(fits <= Double(budget.limit) * 1.001)
            let gigabytes = (Double(bytes) / 1_000_000_000).formatted(.number.precision(.fractionLength(1)))
            let advice = "coarsen to \(suggestion.formatted()) mm or split the part."
            #expect(error.userMessage == "This needs about \(gigabytes) GB at 0.1 mm; \(advice)")
        }
    }

    @Test func aTinyResolutionIsRefusedNotATrap() async throws {
        let budget = MeshingBudget(physicalMemory: 64_000_000_000)
        let evaluator = CPUBatchEvaluator(solid)
        do {
            try await budget.check(solid, resolution: 1e-9, using: evaluator)
            Issue.record("the job should have been refused")
        } catch let error as ImplicitMeshingError {
            guard case .tooBig = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func aSolidWithNoSurfaceIsRefusedAsEmpty() async throws {
        let move = RigidMove(origin: Vector3(20, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let apart = ImplicitSolid.intersect([.sphere(radius: 3), .moved(.sphere(radius: 3), move)], blend: .constant(0))
        do {
            try await MeshingBudget(physicalMemory: 64_000_000_000).check(apart, resolution: 0.5, using: CPUBatchEvaluator(apart))
            Issue.record("the job should have been refused")
        } catch let error as ImplicitMeshingError {
            #expect(error == .empty)
        }
    }

    @Test func theMessagesAreTheSpecs() {
        #expect(ImplicitMeshingError.tooBig(bytes: 12_340_000_000, resolution: 0.1, suggestion: 0.35).userMessage
            == "This needs about 12.3 GB at 0.1 mm; coarsen to 0.35 mm or split the part.")
        #expect(ImplicitMeshingError.empty.userMessage == "There is no surface to mesh: the shape is empty, or smaller than a voxel.")
    }
}
