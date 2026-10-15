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

    /// The engine's mesh of the bricks, or `nil` when it does not mesh or cannot take this request: the CPU mesher then does it.
    public func meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        do {
            return try await engine.meshBricks(program, request, progress: progress)
        } catch is ImplicitCompileError {
            return nil
        }
    }
}
