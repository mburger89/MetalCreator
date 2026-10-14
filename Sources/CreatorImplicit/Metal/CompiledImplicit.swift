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

    /// The name of the kernel in `source`.
    public static let kernelName = "evaluateImplicit"
}

/// Why a solid can't run on the GPU.
public enum ImplicitCompileError: Error, Equatable, Sendable {
    /// Some part of the tree has no Metal form; the evaluation runs on the CPU instead.
    case unsupported(String)
    /// Metal refused the generated source, which is a bug here; the text is Metal's.
    case metal(String)
}
