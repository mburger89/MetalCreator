/// The six meshing pipelines of one shape.
struct HLSLMeshPipelines: Sendable {
    var clear: any ComputePipeline
    var sample: any ComputePipeline
    var classify: any ComputePipeline
    var number: any ComputePipeline
    var place: any ComputePipeline
    var emit: any ComputePipeline
}

/// What one mesh needs that does not change from attempt to attempt (Metal's `MeshJob`).
struct HLSLMeshJob: Sendable {
    var pipelines: HLSLMeshPipelines
    var solid: HLSLImplicitEngine.Prepared
    var bricks: any ComputeBuffer
    var axes: any ComputeBuffer
    var cube: any ComputeBuffer
    var parameters: KernelParameters
    var brickCount: Int
    var started: Int
    var tuning: HLSLImplicitEngine.MeshTuning
}

/// One attempt at one table size (Metal's `MeshRun` and `MeshBuffers`), and the synchronous builders of its batches.
struct HLSLMeshRun: Sendable {
    var job: HLSLMeshJob
    var samples: any ComputeBuffer
    var keys: any ComputeBuffer
    var slotVertex: any ComputeBuffer
    var counters: any ComputeBuffer
    var positions: any ComputeBuffer
    var normals: any ComputeBuffer
    var indices: any ComputeBuffer
    let slots: Int

    init(_ job: HLSLMeshJob, slots: Int, on backend: any ImplicitComputeBackend) throws {
        self.job = job
        self.slots = slots
        samples = try backend.makeBuffer(length: job.tuning.batchBricks * 729 * 4)
        keys = try backend.makeBuffer(length: slots * 4)
        slotVertex = try backend.makeBuffer(length: slots * 4)
        counters = try backend.makeBuffer(length: ImplicitMeshShaderLibrary.Counter.count * 4)
        positions = try backend.makeBuffer(length: 16)
        normals = try backend.makeBuffer(length: 16)
        indices = try backend.makeBuffer(length: 16)
        self.job.parameters.mask = UInt32(slots - 1)
    }

    /// The counters zeroed and the table emptied (Metal: a blit of 0xFF), in ranges of at most 2^20 slots.
    func clearing() -> ComputeBatch {
        let zeros = [UInt8](repeating: 0, count: ImplicitMeshShaderLibrary.Counter.count * 4)
        var batch = ComputeBatch(uploads: [ComputeUpload(bytes: zeros, buffer: counters)])
        for range in ComputeBytes.ranges(count: slots, size: 1 << 20) {
            var parameters = job.parameters
            (parameters.firstSlot, parameters.count) = (UInt32(range.lowerBound), UInt32(range.count))
            batch.dispatches.append(ComputeDispatch(kernel: .clear, pipeline: job.pipelines.clear, parameters: parameters, readOnly: [],
                                                    readWrite: [keys], threads: range.count))
        }
        return batch
    }

    /// Steps 1 and 2, or 1 and 5, for one batch of bricks, each in its own pass.
    func brickBatch(_ range: Range<Int>, emitting: Bool) -> ComputeBatch {
        var parameters = job.parameters
        (parameters.firstBrick, parameters.brickCount) = (UInt32(range.lowerBound), UInt32(range.count))
        let sample = ComputeDispatch(kernel: .sample, pipeline: job.pipelines.sample, parameters: parameters,
                                     readOnly: [job.solid.floats, job.solid.ints, job.bricks, job.axes], readWrite: [samples],
                                     threads: range.count * 729)
        let second = emitting
            ? ComputeDispatch(kernel: .emit, pipeline: job.pipelines.emit, parameters: parameters,
                              readOnly: [job.bricks, samples, job.cube, keys, slotVertex], readWrite: [counters, indices],
                              threads: range.count * 512)
            : ComputeDispatch(kernel: .classify, pipeline: job.pipelines.classify, parameters: parameters,
                              readOnly: [job.bricks, samples, job.cube], readWrite: [keys, counters], threads: range.count * 512)
        return ComputeBatch(dispatches: [sample, second])
    }

    /// Step 3 or 4 over one range of table slots.
    func slotBatch(_ range: Range<Int>, placing: Bool) -> ComputeBatch {
        var parameters = job.parameters
        (parameters.firstSlot, parameters.count) = (UInt32(range.lowerBound), UInt32(range.count))
        let dispatch = placing
            ? ComputeDispatch(kernel: .place, pipeline: job.pipelines.place, parameters: parameters,
                              readOnly: [job.solid.floats, job.solid.ints, job.axes, keys, slotVertex], readWrite: [positions, normals],
                              threads: range.count)
            : ComputeDispatch(kernel: .number, pipeline: job.pipelines.number, parameters: parameters, readOnly: [keys],
                              readWrite: [slotVertex, counters], threads: range.count)
        return ComputeBatch(dispatches: [dispatch])
    }

    func readingCounters() -> ComputeBatch {
        ComputeBatch(downloads: [ComputeDownload(buffer: counters, length: ImplicitMeshShaderLibrary.Counter.count * 4)])
    }

    func readingMesh(vertices: Int, triangles: Int) -> ComputeBatch {
        ComputeBatch(downloads: [
            ComputeDownload(buffer: counters, length: ImplicitMeshShaderLibrary.Counter.count * 4),
            ComputeDownload(buffer: positions, length: vertices * 16), ComputeDownload(buffer: normals, length: vertices * 16),
            ComputeDownload(buffer: indices, length: triangles * 12),
        ])
    }

    /// The mesh from `readingMesh`'s bytes; throws when the GPU emitted another count than it counted (Metal's check).
    static func mesh(from read: [[UInt8]], triangles: Int) throws -> BrickMesh {
        let counters = ComputeBytes.values(read[0], as: UInt32.self)
        guard counters[ImplicitMeshShaderLibrary.Counter.triangleCursor] == UInt32(triangles) else {
            throw ImplicitCompileError.engine("the GPU emitted a different number of triangles than it counted")
        }
        func points(_ bytes: [UInt8]) -> [SIMD3<Float>] {
            ComputeBytes.values(bytes, as: SIMD4<Float>.self).map { SIMD3($0.x, $0.y, $0.z) }
        }
        return BrickMesh(positions: points(read[1]), normals: points(read[2]), triangles: ComputeBytes.values(read[3], as: UInt32.self))
    }
}
