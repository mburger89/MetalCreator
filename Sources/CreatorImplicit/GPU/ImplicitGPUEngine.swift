import Foundation

/// A GPU that evaluates compiled implicit solids (implicit spec §4.1, Errata D11 and D13). The rest of the engine depends on this
/// protocol and nothing else of any GPU API: `MetalImplicitEngine` is its only implementation in 7c-1, compiled only where Metal exists,
/// and an SDL3 GPU compute engine for Linux and Windows follows (track xp-c). Where there is no engine the CPU evaluator, which is
/// complete, does everything.
///
/// D13 adds meshing bricks to this protocol (plan 7c-1g); an implementation written now needs only evaluation.
public protocol ImplicitGPUEngine: Sendable {
    /// "Metal" (or the next implementation's name), for the preview badge and the inspector.
    nonisolated var name: String { get }

    /// The device's name, for the inspector.
    var deviceName: String { get async }

    /// Compiles a tree: generates its source (`ImplicitCompiler`, which needs no GPU API) and prepares the pipeline. Throws
    /// `.unsupported` for a tree the GPU has no form for; the caller then uses the CPU. The default does exactly that.
    func compile(_ solid: ImplicitSolid) async throws(ImplicitCompileError) -> CompiledImplicit

    /// Makes the pipeline for `program`'s shape if no solid of that shape has been compiled. Programs of one shape share it.
    func prepare(_ program: CompiledImplicit) async throws(ImplicitCompileError)

    /// The value of `program` at each of `points`, in order. Throws `CancellationError` when the task is cancelled, or `cancel()` is
    /// called, between dispatches.
    func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float]

    /// Ends the batches in flight with `CancellationError`. Batches started after the call run normally.
    func cancel() async
}

extension ImplicitGPUEngine {
    public func compile(_ solid: ImplicitSolid) async throws(ImplicitCompileError) -> CompiledImplicit {
        let program = try ImplicitCompiler.compile(solid)
        try await prepare(program)
        return program
    }
}
