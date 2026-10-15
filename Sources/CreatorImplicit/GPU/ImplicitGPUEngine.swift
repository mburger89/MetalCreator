import Foundation

/// A GPU that evaluates compiled implicit solids (implicit spec §4.1, Errata D11 and D13). The rest of the engine depends on this
/// protocol and nothing else of any GPU API: `MetalImplicitEngine` is its only implementation in 7c-1, compiled only where Metal exists,
/// and an SDL3 GPU compute engine for Linux and Windows follows (track xp-c). Where there is no engine the CPU evaluator, which is
/// complete, does everything.
///
/// D13 adds meshing bricks (plan 7c-1g): `meshBricks` is a requirement with a default that says "not supported", so an engine may
/// evaluate only and leave meshing to the CPU mesher, which stays the reference and the fall-back. The protocol's types are plain
/// values (`CompiledImplicit`, `BrickMeshRequest`, `BrickMesh`): buffers in and buffers out, with no GPU type in them, so an SDL3 GPU
/// compute engine (track xp-c) implements it the way `MetalImplicitEngine` does.
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

    /// The surface of `request`'s bricks, meshed on the GPU with the CPU mesher's marching cubes table, one vertex per lattice edge,
    /// and the Newton snap when `request.snap`. `progress` is called with the fraction done, 0 to 1, in order. Throws `.unsupported`
    /// when this engine does not mesh, or when this request is beyond it (too large for its tables or buffers); the CPU mesher then
    /// does the work. Throws `CancellationError` when the task is cancelled, or `cancel()` is called, between dispatches.
    func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                    progress: @Sendable (Double) -> Void) async throws -> BrickMesh

    /// Ends the batches in flight with `CancellationError`. Batches started after the call run normally.
    func cancel() async
}

extension ImplicitGPUEngine {
    public func compile(_ solid: ImplicitSolid) async throws(ImplicitCompileError) -> CompiledImplicit {
        let program = try ImplicitCompiler.compile(solid)
        try await prepare(program)
        return program
    }

    /// Engines that do not mesh need not say so.
    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        throw ImplicitCompileError.unsupported("meshing bricks")
    }
}
