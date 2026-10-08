/// One screen-space line segment, drawn as an anti-aliased quad. When `a == b` it's a square knob.
struct LineInstance: Equatable {
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var color: SIMD4<Float>
    /// Width in device pixels.
    var width: Float
    /// The pick ID written by the ID pass, or 0.
    var id: UInt32

    init(a: SIMD3<Float>, b: SIMD3<Float>, color: SIMD4<Float>, width: Float, id: UInt32) {
        self.a = a
        self.b = b
        self.color = color
        self.width = width
        self.id = id
    }
}
