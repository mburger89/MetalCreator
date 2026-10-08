/// The ground grid: a square of side `extent` on z = 0, centred at `center`, with lines every `spacing` mm.
struct GridUniforms {
    var center: SIMD2<Float>
    var extent: Float
    var spacing: Float
    var minorColor: SIMD4<Float>
    var majorColor: SIMD4<Float>
}
