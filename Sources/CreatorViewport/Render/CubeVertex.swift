/// A view-cube vertex in cube units, with its tile's colour and where its face's name is painted.
/// - `uv` is the vertex's place in its face's text box: 0…1 across and down the text, outside it beyond the box.
/// - `labelRect` is the face name's `CubeLabelRect` in the atlas (`u0, v0, u1, v1`); all zero means no label.
struct CubeVertex: Equatable {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var uv: SIMD2<Float> = .zero
    var labelRect: SIMD4<Float> = .zero
}
