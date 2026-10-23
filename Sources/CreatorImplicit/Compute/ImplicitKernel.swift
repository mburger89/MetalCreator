/// The HLSL engine's compute kernels (plan xp-c), one source each (`HLSLKernels`): Metal's `evaluateImplicit` and the five meshing kernels of
/// `ImplicitMeshShaderLibrary`, plus `mesh_clear`, because SDL_GPU has no buffer fill. A `ComputeDispatch` lists the storage buffers in declaration order.
public enum ImplicitKernel: String, CaseIterable, Sendable {
    /// floats, ints, points → values.
    case evaluate = "implicit_evaluate"
    /// → keys (emptied over a range of slots).
    case clear = "mesh_clear"
    /// floats, ints, bricks, axes → samples.
    case sample = "mesh_sample"
    /// bricks, samples, cube table → keys, counters.
    case classify = "mesh_classify"
    /// keys → slot vertices, counters.
    case number = "mesh_number"
    /// floats, ints, axes, keys, slot vertices → positions, normals.
    case place = "mesh_place"
    /// bricks, samples, cube table, keys, slot vertices → counters, indices.
    case emit = "mesh_emit"

    public static let threadsPerGroup = 64

    public var bindings: (readOnly: Int, readWrite: Int) {
        switch self {
        case .evaluate: (3, 1)
        case .clear: (0, 1)
        case .sample: (4, 1)
        case .classify: (3, 2)
        case .number: (1, 2)
        case .place: (5, 2)
        case .emit: (5, 2)
        }
    }

    /// Whether the kernel calls the solid's `sdf`, so its source depends on the shape.
    public var usesSDF: Bool { self == .evaluate || self == .sample || self == .place }
}
