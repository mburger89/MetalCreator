/// Per-pass camera data for every vertex shader. Plain SIMD types, so it is the same on every platform: the Metal shaders
/// (`ViewportShaders`) and the HLSL ones (`Shaders/viewport/common.hlsli`) read these 176 bytes, which `GPUDataTests` pins.
struct FrameUniforms {
    var viewProjection: FloatMatrix4
    var view: FloatMatrix4
    var eye: SIMD3<Float>
    var forward: SIMD3<Float>
    /// The render target's size in pixels (lines are sized in pixels).
    var viewportPixels: SIMD2<Float>
    var isOrthographic: UInt32
    var padding: Float
}
