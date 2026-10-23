/// Marching cubes on the HLSL engine (implicit spec §4.3, Errata D13; plan xp-c): `MetalImplicitEngine+Meshing`, step for step, over the HLSL
/// kernels; the batches are built synchronously (`HLSLMeshRun`) and only run here (the Windows Swift 6.4 rules).
extension HLSLImplicitEngine {
    /// Metal's `MeshTuning`, with batch sizes for an SDL dispatch (65,535 groups of 64) and Windows' 2-second GPU watchdog.
    struct MeshTuning: Sendable {
        var batchBricks = 1024
        var slotsPerBrick = 256
        /// 2^25 slots of 4 bytes is the 128 MiB buffer cap (gap XP-G24); Metal's is 2^27.
        var largestTable = 1 << 25
        var slotsPerDispatch = 1 << 18
        var afterBatch: (@Sendable (Int) async -> Void)?
    }

    func tune(_ tuning: MeshTuning) {
        meshTuning = tuning
    }

    @_optimize(none) // Windows Swift 6.4 release: keeps the closure-specialised coroutine clones (compiler crash) from being made.
    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        try Task.checkCancellation()
        guard !request.bricks.isEmpty else { return BrickMesh(positions: [], normals: [], triangles: []) }
        guard let lattice = BrickLattice(request.bricks), lattice.fitsEdgeKeys else {
            throw ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")
        }
        let backend = try backend()
        let job = try await startJob(program, request, lattice, on: backend)
        let largest = min(job.tuning.largestTable, backend.largestBuffer / 4)
        var slots = 1 << max(12, Int.bitWidth - (request.bricks.count * job.tuning.slotsPerBrick - 1).leadingZeroBitCount)
        while true {
            guard slots <= largest else { throw ImplicitCompileError.unsupported("the edge table would pass \(largest) slots") }
            if let mesh = try await attempt(job, slots: slots, on: backend, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }

    /// The six meshing pipelines of `program`'s shape, made once each (a pipeline whose text another shape shares is not made again).
    private func meshPipelines(for program: CompiledImplicit, on backend: any ImplicitComputeBackend) async throws -> HLSLMeshPipelines {
        func pipeline(_ kernel: ImplicitKernel) async throws -> any ComputePipeline {
            guard let source = program.kernels[kernel] else {
                throw ImplicitCompileError.unsupported("a solid compiled for Metal, not HLSL")
            }
            if let known = meshPipelineCache[source.digest] { return known }
            let made = try await backend.makePipeline(source)
            if let raced = meshPipelineCache[source.digest] { return raced }
            meshCompileCount += 1
            meshPipelineCache[source.digest] = made
            return made
        }
        return HLSLMeshPipelines(clear: try await pipeline(.clear), sample: try await pipeline(.sample),
                                 classify: try await pipeline(.classify),
                                 number: try await pipeline(.number), place: try await pipeline(.place), emit: try await pipeline(.emit))
    }

    private func startJob(_ program: CompiledImplicit, _ request: BrickMeshRequest, _ lattice: BrickLattice,
                          on backend: any ImplicitComputeBackend) async throws -> HLSLMeshJob {
        let started = epoch
        let pipelines = try await meshPipelines(for: program, on: backend)
        let solid = try await buffers(for: program, on: backend)
        let brickWords = lattice.relativeBricks(request.bricks)
        let axisValues = lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)
        let bricks = try backend.makeBuffer(length: brickWords.count * 4)
        let axes = try backend.makeBuffer(length: axisValues.count * 4)
        let cube = try backend.makeBuffer(length: MarchingCubesBuffers.words.count * 4)
        _ = try await backend.run(ComputeBatch(uploads: [
            ComputeUpload(bytes: ComputeBytes.bytes(of: brickWords), buffer: bricks),
            ComputeUpload(bytes: ComputeBytes.bytes(of: axisValues), buffer: axes),
            ComputeUpload(bytes: ComputeBytes.bytes(of: MarchingCubesBuffers.words), buffer: cube),
        ]))
        var parameters = solid.parameters
        let size = lattice.points
        (parameters.nx, parameters.ny, parameters.nz) = (UInt32(size.x), UInt32(size.y), UInt32(size.z))
        parameters.snap = request.snap ? 1 : 0
        parameters.resolution = Float(request.resolution)
        return HLSLMeshJob(pipelines: pipelines, solid: solid, bricks: bricks, axes: axes, cube: cube, parameters: parameters,
                           brickCount: request.bricks.count, started: started, tuning: meshTuning)
    }

    /// One run of the steps with a table of `slots`; `nil` when the table proved too small (Metal's `meshAttempt`).
    @_optimize(none) // Windows Swift 6.4 release: takes the progress closure; see `meshBricks`.
    private func attempt(_ job: HLSLMeshJob, slots: Int, on backend: any ImplicitComputeBackend,
                         progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        var run = try HLSLMeshRun(job, slots: slots, on: backend)
        _ = try await backend.run(run.clearing())
        try await sweep(run, emitting: false, from: 0, to: 0.4, on: backend, progress: progress)
        var counts = ComputeBytes.values(try await backend.run(run.readingCounters())[0], as: UInt32.self)
        if counts[ImplicitMeshShaderLibrary.Counter.overflow] != 0 { return nil }
        let triangles = Int(counts[ImplicitMeshShaderLibrary.Counter.triangleTotal])
        try await sweepSlots(run, placing: false, on: backend)
        counts = ComputeBytes.values(try await backend.run(run.readingCounters())[0], as: UInt32.self)
        let vertices = Int(counts[ImplicitMeshShaderLibrary.Counter.vertices])
        guard vertices > 0, triangles > 0 else { return BrickMesh(positions: [], normals: [], triangles: []) }
        run.positions = try backend.makeBuffer(length: vertices * 16)
        run.normals = try backend.makeBuffer(length: vertices * 16)
        run.indices = try backend.makeBuffer(length: triangles * 12)
        try await sweepSlots(run, placing: true, on: backend)
        progress(0.55)
        try await sweep(run, emitting: true, from: 0.55, to: 0.95, on: backend, progress: progress)
        let read = try await backend.run(run.readingMesh(vertices: vertices, triangles: triangles))
        return try HLSLMeshRun.mesh(from: read, triangles: triangles)
    }

    @_optimize(none) // Windows Swift 6.4 release: takes the progress closure; see `meshBricks`.
    private func sweep(_ run: HLSLMeshRun, emitting: Bool, from: Double, to: Double, on backend: any ImplicitComputeBackend,
                       progress: @Sendable (Double) -> Void) async throws {
        let batches = ComputeBytes.ranges(count: run.job.brickCount, size: run.job.tuning.batchBricks)
        for index in batches.indices {
            _ = try await backend.run(run.brickBatch(batches[index], emitting: emitting))
            await run.job.tuning.afterBatch?(index + 1)
            try checkRunning(run.job)
            progress(from + (to - from) * Double(batches[index].upperBound) / Double(run.job.brickCount))
        }
    }

    private func sweepSlots(_ run: HLSLMeshRun, placing: Bool, on backend: any ImplicitComputeBackend) async throws {
        let ranges = ComputeBytes.ranges(count: run.slots, size: run.job.tuning.slotsPerDispatch)
        for index in ranges.indices {
            _ = try await backend.run(run.slotBatch(ranges[index], placing: placing))
            try checkRunning(run.job)
        }
    }

    private func checkRunning(_ job: HLSLMeshJob) throws {
        try Task.checkCancellation()
        if epoch != job.started { throw CancellationError() }
    }
}
