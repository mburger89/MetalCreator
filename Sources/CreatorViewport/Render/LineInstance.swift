/// One screen-space line segment, drawn as an anti-aliased quad. When `a == b` it's a square knob.
struct LineInstance: Equatable {
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var color: SIMD4<Float>
    /// Width in device pixels.
    var width: Float
    /// The pick ID written by the ID pass, or 0.
    var id: UInt32
}
