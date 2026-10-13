/// The field ramp for the tint's fragment shader: the three colours, and in `range` the three values (x low, y middle, z high;
/// w unused). Mirrors `FieldRampUniforms` in `FieldShaders` (stride pinned by `FieldTintDataTests`).
struct FieldRampUniforms {
    var low: SIMD4<Float>
    var mid: SIMD4<Float>
    var high: SIMD4<Float>
    var range: SIMD4<Float>

    init(_ ramp: FieldRamp) {
        low = ramp.low
        mid = ramp.mid
        high = ramp.high
        range = SIMD4(ramp.lowValue, ramp.midValue, ramp.highValue, 0)
    }
}
