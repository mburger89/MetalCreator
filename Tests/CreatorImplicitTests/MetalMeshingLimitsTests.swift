#if canImport(Metal)
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// What the Metal mesher does at its edges (implicit spec Errata D13): small batches, a table that is too small, a request beyond its
/// limits, a part far from the origin, a cancel. Skipped on a machine without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct MetalMeshingLimitsTests {
    static let solid = ImplicitSolid.sphere(radius: 10)

    /// A fresh engine, tuned, and the program and request for `solid`.
    struct Prepared {
        let engine: MetalImplicitEngine
        let program: CompiledImplicit
        let request: BrickMeshRequest

        init(_ solid: ImplicitSolid = MetalMeshingLimitsTests.solid, resolution: Double = 0.53,
             tuning: MetalImplicitEngine.MeshTuning = MetalImplicitEngine.MeshTuning()) async throws {
            guard let engine = MetalImplicitEngine() else { throw ImplicitCompileError.engine("no Metal device") }
            await engine.tune(tuning)
            self.engine = engine
            program = try await engine.compile(solid)
            request = try await MetalMeshingTests.request(solid, resolution: resolution)
        }

        func mesh() async throws -> BrickMesh {
            try await engine.meshBricks(program, request) { _ in }
        }
    }

    static func sameSet(_ a: BrickMesh, _ b: BrickMesh) -> Bool {
        let comparison = MeshComparison(reference: a.triangleMesh, candidate: b.triangleMesh)
        return comparison.unmatched == 0 && comparison.farthest < 1e-6 && a.positions.count == b.positions.count
            && a.triangles.count == b.triangles.count
    }

    @Test func manySmallBatchesMakeTheMeshOneBigBatchDoes() async throws {
        let job = try await Prepared()
        let whole = try await job.mesh()
        #expect(job.request.bricks.count > 50)
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.batchBricks = 7
        await job.engine.tune(tuning)
        let small = try await job.mesh()
        #expect(Self.sameSet(whole, small))
        #expect(MeshTopology(small.triangleMesh).isClosedManifold)
    }

    @Test func aTableThatIsTooSmallIsDoubledUntilItFits() async throws {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        let mesh = try await Prepared(tuning: tuning).mesh()
        let expected = try await Prepared().mesh()
        #expect(mesh.positions.count > 4096, "more vertices than the first table has slots")
        #expect(Self.sameSet(mesh, expected))
    }

    @Test func aMeshBeyondTheLargestTableIsLeftToTheCPU() async throws {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        tuning.largestTable = 4096
        let job = try await Prepared(tuning: tuning)
        await #expect(throws: ImplicitCompileError.self) { _ = try await job.mesh() }
        let (mesh, path) = try await ImplicitMesher(evaluator: GPUBatchEvaluator(engine: job.engine, program: job.program))
            .meshReportingPath(Self.solid, resolution: 0.53, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    @Test func bricksTooFarApartForThirtyTwoBitKeysAreUnsupported() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let program = try await engine.compile(Self.solid)
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func aPartFarFromTheOriginIsMeshedInASmallWindow() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let far = ImplicitSolid.moved(Self.solid, move)
        let selection = await ImplicitEvaluators.make(for: far, choice: .automatic, engine: engine)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(far, resolution: 0.53, quality: .preview)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let bounds = try #require(mesh.bounds)
        #expect(abs(bounds.min.x - 3_990) < 1 && abs(bounds.max.z - 2_510) < 1)
    }

    @Test func theSameBricksMakeTheSameSetOfVerticesAndTriangles() async throws {
        let job = try await Prepared()
        let first = try await job.mesh()
        let second = try await job.mesh()
        // Their order is the threads' and may differ; what they hold may not.
        #expect(Self.sameSet(first, second))
    }

    @Test func aMeshOfSeveralRangesOfSlotsIsTheMeshOneRangeMakes() async throws {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.slotsPerDispatch = 1_000
        let ranges = try await Prepared(tuning: tuning).mesh()
        let whole = try await Prepared().mesh()
        #expect(ranges.positions.count > 1_000, "more vertices than one range of slots")
        #expect(Self.sameSet(ranges, whole))
        #expect(MeshTopology(ranges.triangleMesh).isClosedManifold)
    }

    /// A mesh of many small batches, so a cancel has somewhere to land between two of them.
    static func manyBatches() async throws -> Prepared {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        let job = try await Prepared(.sphere(radius: 20), resolution: 0.4, tuning: tuning)
        #expect(job.request.bricks.count > 40, "ten batches or more")
        return job
    }

    /// The next mesh on the engine, after a cancel: it runs whole.
    static func expectTheNextMeshRuns(_ engine: MetalImplicitEngine) async throws {
        let small = try await MetalMeshingTests.request(.sphere(radius: 3), resolution: 0.5)
        let after = try await engine.meshBricks(try await engine.compile(.sphere(radius: 3)), small) { _ in }
        #expect(MeshTopology(after.triangleMesh).isClosedManifold)
    }

    @Test func cancellingTheTaskEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        let seen = ProgressLog()
        // The progress callback runs on the meshing task after each batch: it cancels that task after the first.
        let running = Task {
            try await job.engine.meshBricks(job.program, job.request) { fraction in
                seen.append(fraction)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await running.value }
        #expect(seen.values.count == 1, "it ended at the next batch, not after the whole mesh: \(seen.values.count) reports")
        try await Self.expectTheNextMeshRuns(job.engine)
    }

    @Test func anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        // After the first batch the engine itself is cancelled, which bumps its epoch (an edit does this to a running mesh).
        tuning.afterBatch = { [engine = job.engine] batch in
            if batch == 1 { await engine.cancel() }
        }
        await job.engine.tune(tuning)
        let seen = ProgressLog()
        await #expect(throws: CancellationError.self) {
            _ = try await job.engine.meshBricks(job.program, job.request) { seen.append($0) }
        }
        #expect(seen.values.isEmpty, "the first batch's check ended it before its report")
        tuning.afterBatch = nil
        await job.engine.tune(tuning)
        try await Self.expectTheNextMeshRuns(job.engine)
    }
}
#endif
