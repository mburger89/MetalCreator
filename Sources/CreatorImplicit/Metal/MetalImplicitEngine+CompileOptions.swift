#if canImport(Metal)
@preconcurrency import Metal

extension MetalImplicitEngine {
    /// The options both of the engine's libraries (the evaluation kernel and the meshing kernels) are compiled with: exact IEEE arithmetic.
    ///
    /// Metal's default is fast math, which may reassociate and contract a float expression. The CPU evaluator is the reference the GPU is
    /// held to, and a surface lying on a lattice plane (the bounds faces, which `BrickPlan` pads by exactly one voxel) is only the CPU's exact 0
    /// when the shell's `(length + min - r) - centre` is computed as written; DXC's fast math broke it on Direct3D 12 (spec D21 (7)). So
    /// `.safe` math keeps the operations as written and `.precise` makes the library functions the correctly rounded ones. The options are a
    /// constant of the engine: every pipeline is compiled with them, so the source-keyed pipeline cache needs no options in its key.
    /// Deployment target is macOS 26, so `mathMode` and `mathFloatingPointFunctions` (macOS 15) need no `fastMathEnabled` fallback.
    static func exactCompileOptions() -> MTLCompileOptions {
        let options = MTLCompileOptions()
        options.mathMode = .safe
        options.mathFloatingPointFunctions = .precise
        return options
    }
}
#endif
