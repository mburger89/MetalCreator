#if canImport(Metal)
import Foundation
@preconcurrency import Metal

/// Marching cubes on the GPU (implicit spec §4.3, Errata D13): the five kernels of `ImplicitMeshShaderLibrary` run over the bricks of
/// a `BrickMeshRequest`. The CPU mesher stays the reference; this is the same algorithm with the same table, one vertex per lattice
/// edge and the same Newton step, and `GPUMeshAgreementTests` holds the two to the same topology and 1e-4 mm.
extension MetalImplicitEngine {
    /// The compiled meshing kernels of one shape.
    struct MeshPipelines {
        var sample: any MTLComputePipelineState
        var classify: any MTLComputePipelineState
        var number: any MTLComputePipelineState
        var place: any MTLComputePipelineState
        var emit: any MTLComputePipelineState
    }

    /// `MeshParams` of the shader, field for field.
    struct MeshParameters {
        var firstBrick: UInt32 = 0
        var brickCount: UInt32 = 0
        var nx: UInt32 = 0
        var ny: UInt32 = 0
        var nz: UInt32 = 0
        var mask: UInt32 = 0
        var snap: UInt32 = 0
        var resolution: Float = 0
        var firstSlot: UInt32 = 0
    }

    /// What one mesh needs that does not change from attempt to attempt.
    private struct MeshJob {
        var pipelines: MeshPipelines
        var solid: Prepared
        var bricks: any MTLBuffer
        var axes: any MTLBuffer
        var cube: any MTLBuffer
        var parameters: MeshParameters
        var brickCount: Int
        var started: Int
        /// How many table slots one command buffer takes in the number and place steps.
        var slotsPerDispatch: Int
    }

    /// One attempt at one table size: its buffers and the parameters the dispatches are made with.
    private struct MeshRun {
        var job: MeshJob
        var buffers: MeshBuffers
        var parameters: MeshParameters
        let slots: Int
        let batch: Int
    }

    /// The buffers of one attempt at one table size.
    private struct MeshBuffers {
        var samples: any MTLBuffer
        var keys: any MTLBuffer
        var slotVertex: any MTLBuffer
        var counters: any MTLBuffer
        var positions: any MTLBuffer
        var normals: any MTLBuffer
        var indices: any MTLBuffer
    }

    /// The sizes meshing works in. The defaults are the engine's; the tests turn them down to reach the paths a small mesh never takes.
    struct MeshTuning {
        /// How many bricks are sampled and meshed in one pair of dispatches (4,096 as in implicit spec §4.2: 12 MB of samples).
        var batchBricks = 4096
        /// The first table has this many slots for each brick; a table that proves too small is doubled.
        var slotsPerBrick = 256
        /// The most slots a table gets (8 bytes each); a mesh needing more is left to the CPU.
        var largestTable = 1 << 27
        /// How many table slots one command buffer numbers or places: a slot costs up to nine evaluations of the solid, so this keeps
        /// one buffer to the same order of work as the evaluator's (`pointsPerDispatch` points).
        var slotsPerDispatch = 1 << 20
        /// Called with the number of the batch just run (from 1), after its command buffer and before the check for a cancel: the
        /// tests cancel from it, at a known point. Nothing in the engine sets it.
        var afterBatch: (@Sendable (Int) async -> Void)?
    }

    /// Replaces the sizes meshing works in, for the tests.
    func tune(_ tuning: MeshTuning) {
        meshTuning = tuning
    }

    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        try Task.checkCancellation()
        guard !request.bricks.isEmpty else { return BrickMesh(positions: [], normals: [], triangles: []) }
        guard let lattice = BrickLattice(request.bricks), lattice.fitsEdgeKeys else {
            throw ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")
        }
        let started = epoch
        let pipelines = try await meshPipelines(for: program)
        let size = lattice.points
        var parameters = MeshParameters()
        (parameters.nx, parameters.ny, parameters.nz) = (UInt32(size.x), UInt32(size.y), UInt32(size.z))
        parameters.snap = request.snap ? 1 : 0
        parameters.resolution = Float(request.resolution)
        let job = MeshJob(
            pipelines: pipelines, solid: try buffers(for: program), bricks: try meshUpload(lattice.relativeBricks(request.bricks)),
            axes: try meshUpload(lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)),
            cube: try meshUpload(MarchingCubesBuffers.words), parameters: parameters, brickCount: request.bricks.count, started: started,
            slotsPerDispatch: meshTuning.slotsPerDispatch)
        let tuning = meshTuning
        var slots = 1 << max(12, Int.bitWidth - (request.bricks.count * tuning.slotsPerBrick - 1).leadingZeroBitCount)
        while true {
            guard slots <= tuning.largestTable else {
                throw ImplicitCompileError.unsupported("the edge table would pass \(tuning.largestTable) slots")
            }
            if let mesh = try await meshAttempt(job, slots: slots, batch: tuning.batchBricks, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }

    /// One run of the five steps with a table of `slots`; `nil` when the table proved too small.
    private func meshAttempt(_ job: MeshJob, slots: Int, batch: Int, progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        var run = try await startRun(job, slots: slots, batch: batch)
        // Steps 1 and 2 for every batch: afterwards the table holds every edge the surface crosses.
        try await sweep(&run, emitting: false, from: 0, to: 0.4, progress: progress)
        var counts = readCounters(run.buffers)
        if counts[ImplicitMeshShaderLibrary.Counter.overflow] != 0 { return nil }
        let triangles = Int(counts[ImplicitMeshShaderLibrary.Counter.triangleTotal])
        try await sweepSlots(&run, run.job.pipelines.number)
        counts = readCounters(run.buffers)
        let vertices = Int(counts[ImplicitMeshShaderLibrary.Counter.vertices])
        guard vertices > 0, triangles > 0 else { return BrickMesh(positions: [], normals: [], triangles: []) }
        run.buffers.positions = try meshBuffer(vertices * 16)
        run.buffers.normals = try meshBuffer(vertices * 16)
        run.buffers.indices = try meshBuffer(triangles * 12)
        try await sweepSlots(&run, run.job.pipelines.place)
        progress(0.55)
        try await sweep(&run, emitting: true, from: 0.55, to: 0.95, progress: progress)
        guard readCounters(run.buffers)[ImplicitMeshShaderLibrary.Counter.triangleCursor] == UInt32(triangles) else {
            throw ImplicitCompileError.engine("the GPU emitted a different number of triangles than it counted")
        }
        return BrickMesh(positions: Self.read(run.buffers.positions, SIMD3<Float>.self, count: vertices),
                         normals: Self.read(run.buffers.normals, SIMD3<Float>.self, count: vertices),
                         triangles: Self.read(run.buffers.indices, UInt32.self, count: triangles * 3))
    }

    /// The buffers of an attempt, the counters cleared and the table emptied.
    private func startRun(_ job: MeshJob, slots: Int, batch: Int) async throws -> MeshRun {
        var parameters = job.parameters
        parameters.mask = UInt32(slots - 1)
        let counterCount = ImplicitMeshShaderLibrary.Counter.count
        let buffers = MeshBuffers(
            samples: try meshBuffer(batch * 729 * 4), keys: try meshBuffer(slots * 4), slotVertex: try meshBuffer(slots * 4),
            counters: try meshBuffer(counterCount * 4), positions: try meshBuffer(16), normals: try meshBuffer(16),
            indices: try meshBuffer(16))
        buffers.counters.contents().initializeMemory(as: UInt32.self, repeating: 0, count: counterCount)
        try await submit { commands in
            let blit = commands.makeBlitCommandEncoder()
            blit?.fill(buffer: buffers.keys, range: 0..<buffers.keys.length, value: 0xFF)
            blit?.endEncoding()
        }
        return MeshRun(job: job, buffers: buffers, parameters: parameters, slots: slots, batch: batch)
    }

    /// Samples every batch of bricks and then classifies its cubes (step 2) or emits its triangles (step 5); progress runs `from` to `to`.
    private func sweep(_ run: inout MeshRun, emitting: Bool, from: Double, to: Double, progress: @Sendable (Double) -> Void) async throws {
        let total = run.job.brickCount
        for first in stride(from: 0, to: total, by: run.batch) {
            let count = min(run.batch, total - first)
            (run.parameters.firstBrick, run.parameters.brickCount) = (UInt32(first), UInt32(count))
            try await submit { encoder in
                bind(encoder, run.job, run.buffers, &run.parameters)
                dispatch(encoder, run.job.pipelines.sample, threads: count * 729)
                dispatch(encoder, emitting ? run.job.pipelines.emit : run.job.pipelines.classify, threads: count * 512)
            }
            await meshTuning.afterBatch?(first / run.batch + 1)
            try checkRunning(run.job)
            progress(from + (to - from) * Double(first + count) / Double(total))
        }
    }

    /// Runs a per-slot kernel (`meshNumber`, `meshPlace`) over the whole table, `slotsPerDispatch` slots to a command buffer.
    private func sweepSlots(_ run: inout MeshRun, _ pipeline: any MTLComputePipelineState) async throws {
        for first in stride(from: 0, to: run.slots, by: run.job.slotsPerDispatch) {
            run.parameters.firstSlot = UInt32(first)
            let count = min(run.job.slotsPerDispatch, run.slots - first)
            try await submit { encoder in
                bind(encoder, run.job, run.buffers, &run.parameters)
                dispatch(encoder, pipeline, threads: count)
            }
            try checkRunning(run.job)
        }
    }

    // MARK: Pipelines

    /// The meshing kernels for `program`'s shape, compiled once: they are the program's source with the kernels appended.
    private func meshPipelines(for program: CompiledImplicit) async throws -> MeshPipelines {
        if let known = meshPipelines[program.shape] { return known }
        do {
            let source = ImplicitMeshShaderLibrary.source(extending: program)
            let library = try await device.makeLibrary(source: source, options: Self.exactCompileOptions())
            var made: [any MTLComputePipelineState] = []
            for name in ImplicitMeshShaderLibrary.kernelNames {
                guard let function = library.makeFunction(name: name) else {
                    throw ImplicitCompileError.engine("the kernel \(name) is missing")
                }
                made.append(try await device.makeComputePipelineState(function: function))
            }
            let pipelines = MeshPipelines(sample: made[0], classify: made[1], number: made[2], place: made[3], emit: made[4])
            meshCompileCount += 1
            if let raced = meshPipelines[program.shape] { return raced }
            meshPipelines[program.shape] = pipelines
            return pipelines
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw ImplicitCompileError.engine(error.localizedDescription)
        }
    }

    // MARK: Encoding

    private func bind(_ encoder: any MTLComputeCommandEncoder, _ job: MeshJob, _ buffers: MeshBuffers, _ parameters: inout MeshParameters) {
        typealias Binding = ImplicitMeshShaderLibrary.Binding
        encoder.setBuffer(job.bricks, offset: 0, index: Binding.bricks)
        encoder.setBuffer(job.axes, offset: 0, index: Binding.axes)
        encoder.setBuffer(buffers.samples, offset: 0, index: Binding.samples)
        encoder.setBuffer(job.solid.parameters, offset: 0, index: Binding.parameters)
        encoder.setBuffer(job.solid.integers, offset: 0, index: Binding.integers)
        encoder.setBuffer(job.solid.tables, offset: 0, index: Binding.tables)
        encoder.setBuffer(job.solid.pool, offset: 0, index: Binding.pool)
        encoder.setBuffer(job.solid.images, offset: 0, index: Binding.images)
        encoder.setBytes(&parameters, length: MemoryLayout<MeshParameters>.stride, index: Binding.meshParameters)
        encoder.setBuffer(job.cube, offset: 0, index: Binding.cubeTable)
        encoder.setBuffer(buffers.keys, offset: 0, index: Binding.keys)
        encoder.setBuffer(buffers.slotVertex, offset: 0, index: Binding.slotVertex)
        encoder.setBuffer(buffers.counters, offset: 0, index: Binding.counters)
        encoder.setBuffer(buffers.positions, offset: 0, index: Binding.positions)
        encoder.setBuffer(buffers.normals, offset: 0, index: Binding.normals)
        encoder.setBuffer(buffers.indices, offset: 0, index: Binding.indices)
    }

    private func dispatch(_ encoder: any MTLComputeCommandEncoder, _ pipeline: any MTLComputePipelineState, threads: Int) {
        guard threads > 0 else { return }
        encoder.setComputePipelineState(pipeline)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
    }

    /// Encodes with `encode` into one command buffer, runs it and waits.
    private func submit(_ encode: (any MTLCommandBuffer) -> Void) async throws {
        guard let commands = queue.makeCommandBuffer() else { throw ImplicitCompileError.engine("a GPU command buffer could not be made") }
        encode(commands)
        await withCheckedContinuation { continuation in
            commands.addCompletedHandler { _ in continuation.resume() }
            commands.commit()
        }
        if let error = commands.error { throw ImplicitCompileError.engine(error.localizedDescription) }
    }

    /// Runs one compute encoder: `encode` fills it.
    private func submit(_ encode: (any MTLComputeCommandEncoder) -> Void) async throws {
        try await submit { (commands: any MTLCommandBuffer) in
            guard let encoder = commands.makeComputeCommandEncoder() else { return }
            encode(encoder)
            encoder.endEncoding()
        }
    }

    private func checkRunning(_ job: MeshJob) throws {
        try Task.checkCancellation()
        if epoch != job.started { throw CancellationError() }
    }

    // MARK: Buffers

    /// A buffer of `length` bytes, or "unsupported": a request this big is the CPU's.
    private func meshBuffer(_ length: Int) throws -> any MTLBuffer {
        guard length <= device.maxBufferLength, let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes could not be made")
        }
        return buffer
    }

    private func meshUpload<T>(_ values: [T]) throws -> any MTLBuffer {
        let buffer = try meshBuffer(values.count * MemoryLayout<T>.stride)
        values.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { buffer.contents().copyMemory(from: base, byteCount: bytes.count) }
        }
        return buffer
    }

    private func readCounters(_ buffers: MeshBuffers) -> [UInt32] {
        Self.read(buffers.counters, UInt32.self, count: ImplicitMeshShaderLibrary.Counter.count)
    }

    private static func read<T>(_ buffer: any MTLBuffer, _ type: T.Type, count: Int) -> [T] {
        Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: T.self, capacity: count), count: count))
    }
}
#endif
