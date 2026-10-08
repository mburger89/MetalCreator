import simd

/// A column-major 4×4 matrix in Double, converted to `simd_float4x4` for the GPU.
struct Matrix4: Equatable, Sendable {
    var c0: SIMD4<Double>
    var c1: SIMD4<Double>
    var c2: SIMD4<Double>
    var c3: SIMD4<Double>

    static let identity = Matrix4(c0: [1, 0, 0, 0], c1: [0, 1, 0, 0], c2: [0, 0, 1, 0], c3: [0, 0, 0, 1])

    static func * (m: Matrix4, v: SIMD4<Double>) -> SIMD4<Double> {
        m.c0 * v.x + m.c1 * v.y + m.c2 * v.z + m.c3 * v.w
    }

    static func * (a: Matrix4, b: Matrix4) -> Matrix4 {
        Matrix4(c0: a * b.c0, c1: a * b.c1, c2: a * b.c2, c3: a * b.c3)
    }

    var float: simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(c0), SIMD4<Float>(c1), SIMD4<Float>(c2), SIMD4<Float>(c3)))
    }
}
