import Foundation

/// The GPU engine of Linux and Windows (plan xp-c; cross-platform erratum E8, implicit erratum D21), built as `MetalImplicitEngine` is: a solid's HLSL
/// (`ImplicitCompiler.compileHLSL`, the Metal walk in the HLSL dialect) is compiled while the app runs, one pipeline per kernel source, cached by the
/// source's digest (the least recently used of 64 dropped, as Metal's); a few compiled solids keep their buffers. The backend is made on first use,
/// inside the actor, so the device is never made on the main actor.
public actor HLSLImplicitEngine: ImplicitGPUEngine {
    /// A solid's uploaded buffers (the five of Metal's, packed in two) and the uniform block's solid-specific words.
    struct Prepared: Sendable {
        var floats: any ComputeBuffer
        var ints: any ComputeBuffer
        var parameters: KernelParameters
        var used: Int
    }

    public nonisolated let name: String
    private let makeBackend: @Sendable () -> ComputeBackendState
    private var state: ComputeBackendState?
    private var pipelines: [String: (pipeline: any ComputePipeline, used: Int)] = [:]
    private var prepared: [UUID: Prepared] = [:]
    private var clock = 0

    private static let preparedLimit = 8
    /// How many evaluation pipelines are kept (Metal's `pipelineLimit`).
    static let pipelineLimit = 64
    /// The most points one dispatch takes (Metal's is 2^22; an SDL dispatch has at most 65,535 groups of 64).
    public static let pointsPerDispatch = 1 << 20

    /// Evaluation pipelines compiled (a cache hit doesn't count), as `MetalImplicitEngine.compileCount`.
    public private(set) var compileCount = 0
    /// The meshing pipelines by digest (`+Meshing`), kept like Metal's mesh pipelines; the four that do not call `sdf` are shared by every shape.
    var meshPipelineCache: [String: any ComputePipeline] = [:]
    public internal(set) var meshCompileCount = 0
    public internal(set) var meshesMade = 0
    var meshTuning = MeshTuning()
    var epoch = 0
    let dispatchSize: Int
    private var afterDispatch: (@Sendable (Int) async -> Void)?

    public init(name: String, backend: @escaping @Sendable () -> ComputeBackendState, dispatchSize: Int = pointsPerDispatch) {
        self.name = name
        makeBackend = backend
        self.dispatchSize = max(1, min(dispatchSize, Self.pointsPerDispatch))
    }

    func setAfterDispatch(_ hook: (@Sendable (Int) async -> Void)?) {
        afterDispatch = hook
    }

    private func resolvedState() -> ComputeBackendState {
        if let state { return state }
        let made = makeBackend()
        state = made
        return made
    }

    func backend() throws(ImplicitCompileError) -> any ImplicitComputeBackend {
        switch resolvedState() {
        case .ready(let backend): return backend
        case .absent(let why): throw .unsupported(why)
        case .broken(let why): throw .engine(why)
        }
    }

    public var availability: ImplicitEngineAvailability {
        switch resolvedState() {
        case .ready: .available
        case .absent(let why): .absent(why)
        case .broken(let why): .broken(why)
        }
    }

    public var deviceName: String {
        if case .ready(let backend) = resolvedState() { return backend.deviceName }
        return name
    }

    public func compile(_ solid: ImplicitSolid) async throws(ImplicitCompileError) -> CompiledImplicit {
        let program = try ImplicitCompiler.compileHLSL(solid)
        try await prepare(program)
        return program
    }

    /// Compiles `program`'s evaluation kernel if no solid of its shape has been.
    public func prepare(_ program: CompiledImplicit) async throws(ImplicitCompileError) {
        _ = try await evaluationPipeline(for: program)
    }

    private func evaluationPipeline(for program: CompiledImplicit) async throws(ImplicitCompileError) -> any ComputePipeline {
        guard program.language == .hlsl, let source = program.kernels[.evaluate] else {
            throw .unsupported("a solid compiled for Metal, not HLSL")
        }
        clock += 1
        if let known = pipelines[source.digest] {
            pipelines[source.digest] = (known.pipeline, clock)
            return known.pipeline
        }
        let backend = try backend()
        let made: any ComputePipeline
        do {
            made = try await backend.makePipeline(source)
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw .engine(String(describing: error))
        }
        // A second compile of the same shape that finished first is the one kept, and only the one kept is counted (as Metal's).
        if let raced = pipelines[source.digest] { return raced.pipeline }
        compileCount += 1
        clock += 1
        pipelines[source.digest] = (made, clock)
        if pipelines.count > Self.pipelineLimit, let oldest = pipelines.min(by: { $0.value.used < $1.value.used })?.key {
            pipelines[oldest] = nil
        }
        return made
    }

    public func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float] {
        try Task.checkCancellation()
        guard !points.isEmpty else { return [] }
        let started = epoch
        let pipeline = try await evaluationPipeline(for: program)
        let backend = try backend()
        let solid = try await buffers(for: program, on: backend)
        let size = min(points.count, dispatchSize)
        let input = try backend.makeBuffer(length: size * 12)
        let output = try backend.makeBuffer(length: size * 4)
        var values: [Float] = []
        values.reserveCapacity(points.count)
        let ranges = ComputeBytes.ranges(count: points.count, size: dispatchSize)
        for index in ranges.indices {
            try Task.checkCancellation()
            if epoch != started { throw CancellationError() }
            let read = try await backend.run(Self.evaluation(points[ranges[index]], pipeline, solid, input, output))
            values += read.first.map { ComputeBytes.values($0, as: Float.self) } ?? []
            await afterDispatch?(index + 1)
        }
        return values
    }

    private static func evaluation(_ points: ArraySlice<SIMD3<Float>>, _ pipeline: any ComputePipeline, _ solid: Prepared,
                                   _ input: any ComputeBuffer, _ output: any ComputeBuffer) -> ComputeBatch {
        var parameters = solid.parameters
        parameters.count = UInt32(points.count)
        return ComputeBatch(
            uploads: [ComputeUpload(bytes: ComputeBytes.packed(points), buffer: input)],
            dispatches: [ComputeDispatch(kernel: .evaluate, pipeline: pipeline, parameters: parameters,
                                         readOnly: [solid.floats, solid.ints, input], readWrite: [output], threads: points.count),
            ],
            downloads: [ComputeDownload(buffer: output, length: points.count * 4)])
    }

    public func cancel() {
        epoch += 1
    }

    /// The solid's buffers, uploaded on first use; the least recently used solid's are dropped past `preparedLimit`.
    func buffers(for program: CompiledImplicit, on backend: any ImplicitComputeBackend) async throws -> Prepared {
        clock += 1
        if var known = prepared[program.id] {
            known.used = clock
            prepared[program.id] = known
            return known
        }
        let floats = program.parameters + program.pool + program.images
        let ints = program.integers + program.tables
        var parameters = KernelParameters()
        parameters.poolBase = UInt32(program.parameters.count)
        parameters.imagesBase = UInt32(program.parameters.count + program.pool.count)
        parameters.tablesBase = UInt32(program.integers.count)
        let entry = Prepared(floats: try backend.makeBuffer(length: floats.count * 4), ints: try backend.makeBuffer(length: ints.count * 4),
                             parameters: parameters, used: clock)
        _ = try await backend.run(ComputeBatch(uploads: [
            ComputeUpload(bytes: ComputeBytes.bytes(of: floats), buffer: entry.floats),
            ComputeUpload(bytes: ComputeBytes.bytes(of: ints), buffer: entry.ints),
        ]))
        prepared[program.id] = entry
        if prepared.count > Self.preparedLimit, let oldest = prepared.min(by: { $0.value.used < $1.value.used })?.key {
            prepared[oldest] = nil
        }
        return entry
    }
}
