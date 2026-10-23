import Foundation

/// An implicit solid turned into Metal (implicit spec §4.1): the source of one `float sdf(...)` function and the kernel that calls it
/// over a batch of points, and the buffers it reads. The source depends on the tree's *shape* only (node kinds, wiring and which
/// settings are fields), so a pipeline compiled for one solid serves every solid of that shape; the numbers are in the buffers.
public struct CompiledImplicit: Sendable {
    /// Names this compiled solid's uploaded buffers.
    public let id = UUID()
    /// The complete Metal source: `ImplicitShaderLibrary`, the generated `sdf` and the kernel `evaluateImplicit`.
    public let source: String
    /// Float parameters (positions, sizes, radii, thresholds).
    public let parameters: [Float]
    /// Integer parameters (sides, flags, octave counts, offsets and sizes into the other buffers).
    public let integers: [Int32]
    /// Block tables of baked distances, and noise seeds.
    public let tables: [Int32]
    /// Block samples and the bounds of unstored blocks.
    public let pool: [Float]
    /// Picture pixels, 0 to 65,535.
    public let images: [Float]

    /// The pipeline cache's key, with the source's hash computed once, here.
    public let shape: ShapeKey
    /// Which language `source` is in.
    public let language: ShaderLanguage
    /// The HLSL kernels' sources (plan xp-c), empty for Metal.
    public let kernels: [ImplicitKernel: KernelSource]

    init(source: String, parameters: [Float], integers: [Int32], tables: [Int32], pool: [Float], images: [Float],
         language: ShaderLanguage = .msl, kernels: [ImplicitKernel: KernelSource] = [:]) {
        self.source = source
        self.parameters = parameters
        self.integers = integers
        self.tables = tables
        self.pool = pool
        self.images = images
        shape = ShapeKey(source)
        self.language = language
        self.kernels = kernels
    }

    /// The name of the kernel in `source`.
    public static let kernelName = "evaluateImplicit"
}

/// A compiled source as a dictionary key: hashing a long string on every lookup is the cost this avoids.
public struct ShapeKey: Hashable, Sendable {
    public let source: String
    private let digest: Int

    public init(_ source: String) {
        self.source = source
        var hasher = Hasher()
        hasher.combine(source)
        digest = hasher.finalize()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(digest)
    }

    public static func == (lhs: ShapeKey, rhs: ShapeKey) -> Bool {
        lhs.digest == rhs.digest && lhs.source == rhs.source
    }
}

/// Why a solid can't run on the GPU.
public enum ImplicitCompileError: Error, Equatable, Sendable {
    /// Some part of the tree has no GPU form; the evaluation runs on the CPU instead.
    case unsupported(String)
    /// The GPU engine refused the generated source or a buffer, which is a bug here; the text is the engine's (Metal's, today).
    case engine(String)
}
