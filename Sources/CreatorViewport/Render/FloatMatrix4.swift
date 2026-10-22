/// A column-major 4×4 matrix in Float, as the GPU reads it: four columns of `SIMD4<Float>` and nothing from `simd`, so it
/// exists on every platform. Its 64 bytes are what `simd_float4x4` was (MSL's `float4x4`; HLSL reads the columns one by one).
struct FloatMatrix4: Equatable, Sendable {
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var c3: SIMD4<Float>

    static let identity = FloatMatrix4(c0: [1, 0, 0, 0], c1: [0, 1, 0, 0], c2: [0, 0, 1, 0], c3: [0, 0, 0, 1])
}
