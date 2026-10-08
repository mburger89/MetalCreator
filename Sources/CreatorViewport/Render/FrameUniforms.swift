import simd

/// Per-pass camera data for every vertex shader.
struct FrameUniforms {
    var viewProjection: simd_float4x4
    var view: simd_float4x4
    var eye: SIMD3<Float>
    var forward: SIMD3<Float>
    /// The render target's size in pixels (lines are sized in pixels).
    var viewportPixels: SIMD2<Float>
    var isOrthographic: UInt32
    var padding: Float
}
