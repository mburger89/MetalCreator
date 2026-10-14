/// The fast path of `ImplicitBatchEvaluator`: a compiled solid evaluated by an `ImplicitGPUEngine`.
public struct GPUBatchEvaluator: ImplicitBatchEvaluator {
    public let engine: any ImplicitGPUEngine
    public let program: CompiledImplicit

    public init(engine: any ImplicitGPUEngine, program: CompiledImplicit) {
        self.engine = engine
        self.program = program
    }

    public var engineName: String { engine.name }

    public func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await engine.evaluate(program, at: points)
    }
}
