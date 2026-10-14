#if canImport(Metal)
import Foundation
@preconcurrency import Metal

/// Runs compiled implicits on the GPU (implicit spec §4.1). One engine per device: it compiles each *shape* once (the pipeline cache is
/// keyed by the generated source) and keeps the buffers of the few compiled solids most recently used, so meshing batch after batch
/// uploads a solid's tables once. The only file that imports Metal (Errata D11), compiled only where Metal exists.
public actor MetalImplicitEngine: ImplicitGPUEngine {
    /// The engine for the system's GPU, or `nil` on a machine with none.
    public static let shared: MetalImplicitEngine? = MetalImplicitEngine()

    /// A solid's uploaded parameters.
    struct Prepared {
        var parameters: any MTLBuffer
        var integers: any MTLBuffer
        var tables: any MTLBuffer
        var pool: any MTLBuffer
        var images: any MTLBuffer
        var used: Int
    }

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    private var pipelines: [ShapeKey: (state: any MTLComputePipelineState, used: Int)] = [:]
    private var prepared: [UUID: Prepared] = [:]
    private var clock = 0

    /// How many compiled solids keep their buffers.
    private static let preparedLimit = 8
    /// How many compiled pipelines are kept; the least recently used goes first.
    static let pipelineLimit = 64
    /// The most points one dispatch takes (12 bytes in, 4 out each).
    static let pointsPerDispatch = 1 << 22

    /// How many pipelines were compiled (a cache hit doesn't count): the tests use it to see that shapes are shared.
    public private(set) var compileCount = 0

    public nonisolated let name = "Metal"

    /// The meshing kernels of each shape (`MetalImplicitEngine+Meshing.swift`).
    var meshPipelines: [ShapeKey: MeshPipelines] = [:]
    /// How many sets of meshing pipelines were compiled.
    public internal(set) var meshCompileCount = 0
    /// How many meshes `meshBricks` has made: the benchmarks use it to see that a row's meshes were made on the GPU.
    public internal(set) var meshesMade = 0

    /// Bumped by `cancel()`: a batch that started before it ends at its next dispatch.
    var epoch = 0

    /// How many points one dispatch takes: `pointsPerDispatch`, less in tests that need several dispatches without millions of points.
    private let dispatchSize: Int
    /// Called after each dispatch with how many have run in this batch: tests cancel from it, at a known point.
    private var afterDispatch: (@Sendable (Int) async -> Void)?

    public init?() {
        self.init(dispatchSize: Self.pointsPerDispatch)
    }

    init?(dispatchSize: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.dispatchSize = max(1, min(dispatchSize, Self.pointsPerDispatch))
    }

    /// Sets (or clears) the hook called after each dispatch.
    func setAfterDispatch(_ hook: (@Sendable (Int) async -> Void)?) {
        afterDispatch = hook
    }

    public var deviceName: String { device.name }

    /// Compiles `program`'s source if no solid of its shape has been.
    public func prepare(_ program: CompiledImplicit) async throws(ImplicitCompileError) {
        _ = try await pipeline(for: program)
    }

    private func pipeline(for program: CompiledImplicit) async throws(ImplicitCompileError) -> any MTLComputePipelineState {
        clock += 1
        if let known = pipelines[program.shape] {
            pipelines[program.shape] = (known.state, clock)
            return known.state
        }
        do {
            let library = try await device.makeLibrary(source: program.source, options: nil)
            guard let function = library.makeFunction(name: CompiledImplicit.kernelName) else {
                throw ImplicitCompileError.engine("the kernel \(CompiledImplicit.kernelName) is missing")
            }
            let pipeline = try await device.makeComputePipelineState(function: function)
            // A second compile of the same shape that finished first is the one kept, and only the one kept is counted.
            if let raced = pipelines[program.shape] { return raced.state }
            compileCount += 1
            clock += 1
            pipelines[program.shape] = (pipeline, clock)
            if pipelines.count > Self.pipelineLimit, let oldest = pipelines.min(by: { $0.value.used < $1.value.used })?.key {
                pipelines[oldest] = nil
            }
            return pipeline
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw .engine(error.localizedDescription)
        }
    }

    /// The value of `program` at each of `points`.
    public func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float] {
        try Task.checkCancellation()
        guard !points.isEmpty else { return [] }
        let started = epoch
        let pipeline = try await pipeline(for: program)
        let buffers = try buffers(for: program)
        var values: [Float] = []
        values.reserveCapacity(points.count)
        var dispatched = 0
        for start in stride(from: 0, to: points.count, by: dispatchSize) {
            try Task.checkCancellation()
            if epoch != started { throw CancellationError() }
            let slice = points[start..<min(start + dispatchSize, points.count)]
            values += try await dispatch(pipeline, buffers, slice)
            dispatched += 1
            await afterDispatch?(dispatched)
        }
        return values
    }

    /// Ends the batches in flight; the next call to `evaluate` runs.
    public func cancel() {
        epoch += 1
    }

    private func dispatch(_ pipeline: any MTLComputePipelineState, _ buffers: Prepared,
                          _ points: ArraySlice<SIMD3<Float>>) async throws -> [Float] {
        let count = points.count
        // The shader reads packed_float3: 12 bytes a point, where SIMD3<Float> is 16.
        guard let input = device.makeBuffer(length: count * 3 * MemoryLayout<Float>.stride, options: .storageModeShared),
              let output = device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw ImplicitCompileError.engine("a GPU buffer could not be made")
        }
        let packed = input.contents().bindMemory(to: Float.self, capacity: count * 3)
        for (slot, point) in points.enumerated() {
            packed[3 * slot] = point.x
            packed[3 * slot + 1] = point.y
            packed[3 * slot + 2] = point.z
        }
        var total = UInt32(count)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        encoder.setBuffer(buffers.parameters, offset: 0, index: 2)
        encoder.setBuffer(buffers.integers, offset: 0, index: 3)
        encoder.setBuffer(buffers.tables, offset: 0, index: 4)
        encoder.setBuffer(buffers.pool, offset: 0, index: 5)
        encoder.setBuffer(buffers.images, offset: 0, index: 6)
        encoder.setBytes(&total, length: MemoryLayout<UInt32>.size, index: 7)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        await withCheckedContinuation { continuation in
            commands.addCompletedHandler { _ in continuation.resume() }
            commands.commit()
        }
        if let error = commands.error { throw ImplicitCompileError.engine(error.localizedDescription) }
        return Array(UnsafeBufferPointer(start: output.contents().bindMemory(to: Float.self, capacity: count), count: count))
    }

    /// The solid's buffers, uploaded on first use; the least recently used solid's are dropped past `preparedLimit`.
    func buffers(for program: CompiledImplicit) throws -> Prepared {
        clock += 1
        if var known = prepared[program.id] {
            known.used = clock
            prepared[program.id] = known
            return known
        }
        func upload<T>(_ values: [T]) throws -> any MTLBuffer {
            // Metal won't make an empty buffer: a kind of data this shape doesn't use gets four bytes.
            guard let buffer = device.makeBuffer(length: max(values.count * MemoryLayout<T>.stride, 4), options: .storageModeShared)
            else { throw ImplicitCompileError.engine("a GPU buffer could not be made") }
            values.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { buffer.contents().copyMemory(from: base, byteCount: bytes.count) }
            }
            return buffer
        }
        let entry = Prepared(parameters: try upload(program.parameters), integers: try upload(program.integers),
                             tables: try upload(program.tables), pool: try upload(program.pool), images: try upload(program.images),
                             used: clock)
        prepared[program.id] = entry
        if prepared.count > Self.preparedLimit, let oldest = prepared.min(by: { $0.value.used < $1.value.used })?.key {
            prepared[oldest] = nil
        }
        return entry
    }
}
#endif
