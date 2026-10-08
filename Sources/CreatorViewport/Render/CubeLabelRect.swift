/// Where one face name sits in the cube label atlas, in texture coordinates (0…1, v down).
struct CubeLabelRect: Hashable, Sendable {
    var u0: Float
    var v0: Float
    var u1: Float
    var v1: Float

    /// `(u0, v0, u1, v1)`, as `CubeVertex.labelRect` carries it.
    var simd: SIMD4<Float> { SIMD4(u0, v0, u1, v1) }

    func overlaps(_ other: CubeLabelRect) -> Bool {
        u0 < other.u1 && other.u0 < u1 && v0 < other.v1 && other.v0 < v1
    }
}
