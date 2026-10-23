import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Meshing on the HLSL engine (plan xp-c; Errata D13): the basics, as `MetalMeshingTests` for Metal. Agreement with the CPU is `GPUMeshAgreementTests`.
@Suite(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs the HLSL engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct HLSLMeshingTests {
    static func request(_ solid: ImplicitSolid, resolution: Double, snap: Bool = true) async throws -> BrickMeshRequest {
        BrickMeshRequest(plan: try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid)), snap: snap)
    }

    @Test func aSphereMeshedOnTheGPUIsAClosedManifoldWithTheRightVolume() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == engine.name)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: 0.53, quality: .export)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005)
        #expect(mesh.normals.count == mesh.positions.count && mesh.normals.allSatisfy { abs(($0 * $0).sum() - 1) < 1e-4 })
    }

    @Test func withoutTheSnapTheNormalsAreZeroAndTheVerticesAreOnTheLattice() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let program = try await engine.compile(ImplicitFixtures.sphere)
        let request = try await Self.request(ImplicitFixtures.sphere, resolution: 0.53, snap: false)
        let mesh = try await engine.meshBricks(program, request) { _ in }
        #expect(mesh.isConsistent && !mesh.triangles.isEmpty && mesh.normals.allSatisfy { $0 == .zero })
        let step = Float(request.resolution)
        for position in mesh.positions {
            let onLattice = (0..<3).filter { axis in
                let units = (position[axis] - Float(request.origin[axis])) / step
                return abs(units - units.rounded()) < 1e-3
            }
            #expect(onLattice.count >= 2, "\(position) is on a lattice edge")
        }
    }

    /// Review Focus 3: a shape's meshing pipelines are made once; a second shape makes only its three that call `sdf` (the four others are shared).
    @Test func meshingASecondTimeCompilesNoMeshPipeline() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let sphere = try await engine.compile(.sphere(radius: 3))
        let request = try await Self.request(.sphere(radius: 3), resolution: 0.5)
        _ = try await engine.meshBricks(sphere, request) { _ in }
        #expect(await engine.meshCompileCount == 6)
        _ = try await engine.meshBricks(try await engine.compile(.sphere(radius: 4)), request) { _ in }
        #expect(await engine.meshCompileCount == 6, "the same shape")
        let box = try await engine.compile(.box(halfSize: Vector3(2, 2, 2), cornerRadius: 0))
        let boxRequest = try await Self.request(.box(halfSize: Vector3(2, 2, 2), cornerRadius: 0), resolution: 0.5)
        _ = try await engine.meshBricks(box, boxRequest) { _ in }
        #expect(await engine.meshCompileCount == 8, "sample and place for the box; clear, classify, number and emit shared")
    }

    // MARK: The limits (as `MetalMeshingLimitsTests` for Metal; the comparisons are of sets, the order being the threads' on both engines)

    struct Job {
        let engine: HLSLImplicitEngine
        let program: CompiledImplicit
        let request: BrickMeshRequest

        init(_ solid: ImplicitSolid = .sphere(radius: 10), resolution: Double = 0.53,
             tuning: HLSLImplicitEngine.MeshTuning = HLSLImplicitEngine.MeshTuning()) async throws {
            guard let engine = GPUEnginesUnderTest.makeHLSL() else { throw ImplicitCompileError.engine("no HLSL engine") }
            await engine.tune(tuning)
            self.engine = engine
            program = try await engine.compile(solid)
            request = try await HLSLMeshingTests.request(solid, resolution: resolution)
        }

        func mesh() async throws -> BrickMesh { try await engine.meshBricks(program, request) { _ in } }
    }

    static func sameSet(_ a: BrickMesh, _ b: BrickMesh) -> Bool {
        let comparison = MeshComparison(reference: a.triangleMesh, candidate: b.triangleMesh)
        return comparison.unmatched == 0 && comparison.farthest < 1e-6
            && a.positions.count == b.positions.count && a.triangles.count == b.triangles.count
    }

    @Test func manySmallBatchesMakeTheMeshOneBigBatchDoes() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.batchBricks = 7
        let small = try await Job(tuning: tuning)
        #expect(small.request.bricks.count > 50)
        let many = try await small.mesh()
        let one = try await Job().mesh()
        #expect(Self.sameSet(many, one))
    }

    @Test func aTableThatIsTooSmallIsDoubledUntilItFits() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        let mesh = try await Job(tuning: tuning).mesh()
        let reference = try await Job().mesh()
        #expect(mesh.positions.count > 4096 && Self.sameSet(mesh, reference))
    }

    @Test func aMeshOfSeveralRangesOfSlotsIsTheMeshOneRangeMakes() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.slotsPerDispatch = 1_000
        let ranges = try await Job(tuning: tuning).mesh()
        let reference = try await Job().mesh()
        #expect(ranges.positions.count > 1_000 && Self.sameSet(ranges, reference))
    }

    /// Review Focus 4.
    @Test func aMeshBeyondTheLargestTableIsLeftToTheCPU() async throws {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        tuning.largestTable = 4096
        let job = try await Job(tuning: tuning)
        await #expect(throws: ImplicitCompileError.self) { _ = try await job.mesh() }
        let (mesh, path) = try await ImplicitMesher(evaluator: GPUBatchEvaluator(engine: job.engine, program: job.program))
            .meshReportingPath(.sphere(radius: 10), resolution: 0.53, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    /// Review Focus 4: past the 128 MiB buffer cap (2^25 slots), whatever `largestTable` allows.
    @Test func aTablePastTheBufferCapIsUnsupportedBeforeAnyGPUWork() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.largestTable = 1 << 30
        tuning.slotsPerBrick = 1 << 25
        await engine.tune(tuning)
        let program = try await engine.compile(.sphere(radius: 10))
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the edge table would pass \(1 << 25) slots")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func bricksTooFarApartForThirtyTwoBitKeysAreUnsupported() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let program = try await engine.compile(.sphere(radius: 10))
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func aPartFarFromTheOriginIsMeshedInASmallWindow() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let far = ImplicitSolid.moved(.sphere(radius: 10), move)
        let selection = await ImplicitEvaluators.make(for: far, choice: .automatic, engine: engine)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(far, resolution: 0.53, quality: .preview)
        #expect(path == .gpu && MeshTopology(mesh).isClosedManifold)
        let bounds = try #require(mesh.bounds)
        #expect(abs(bounds.min.x - 3_990) < 1 && abs(bounds.max.z - 2_510) < 1)
    }

    static func manyBatches() async throws -> Job {
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        let job = try await Job(.sphere(radius: 20), resolution: 0.4, tuning: tuning)
        #expect(job.request.bricks.count > 40)
        return job
    }

    static func expectTheNextMeshRuns(_ engine: HLSLImplicitEngine) async throws {
        let small = try await request(.sphere(radius: 3), resolution: 0.5)
        let after = try await engine.meshBricks(try await engine.compile(.sphere(radius: 3)), small) { _ in }
        #expect(MeshTopology(after.triangleMesh).isClosedManifold)
    }

    @Test func cancellingTheTaskEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        let seen = ProgressLog()
        let running = Task {
            try await job.engine.meshBricks(job.program, job.request) { fraction in
                seen.append(fraction)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await running.value }
        #expect(seen.values.count == 1)
        try await Self.expectTheNextMeshRuns(job.engine)
    }

    @Test func anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        var tuning = HLSLImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        tuning.afterBatch = { [engine = job.engine] batch in
            if batch == 1 { await engine.cancel() }
        }
        await job.engine.tune(tuning)
        let seen = ProgressLog()
        await #expect(throws: CancellationError.self) {
            _ = try await job.engine.meshBricks(job.program, job.request) { seen.append($0) }
        }
        #expect(seen.values.isEmpty)
        tuning.afterBatch = nil
        await job.engine.tune(tuning)
        try await Self.expectTheNextMeshRuns(job.engine)
    }
}
