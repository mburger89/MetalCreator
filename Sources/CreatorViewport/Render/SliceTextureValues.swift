/// How a slice's numbers are stored in its GPU texture, the same on every platform: a NaN becomes the ramp's middle value (which is
/// why the middle is part of the texture's cache key: a range change without a new generation must refill them), and an infinity is
/// held to the ramp's end it lies beyond.
enum SliceTextureValues {
    /// `value` as stored: NaN is the ramp's middle, ±infinity the ramp's high or low end, anything else as it is.
    static func filled(_ value: Float, ramp: FieldRamp) -> Float {
        if value.isNaN { return ramp.midValue }
        if value == .infinity { return ramp.highValue }
        if value == -.infinity { return ramp.lowValue }
        return value
    }

    /// Every sample of `slice` as stored, row by row from the `-yAxis` edge.
    static func texels(of slice: ViewportSlice) -> [Float] {
        slice.values.map { filled($0, ramp: slice.ramp) }
    }
}
