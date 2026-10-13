/// The colours a field's value is drawn in (fields spec §6, D13): `low` at `lowValue`, `mid` at `midValue` and `high` at
/// `highValue`, blended in straight lines between them and held beyond the ends. The viewport knows nothing of fields: this is
/// numbers and colours only, the colours in the gamma-space RGBA the GPU takes (`HexColor.rgba`). The shader's `field_ramp`
/// does the same sum, and `FieldTintRenderTests` checks the two agree on screen.
public struct FieldRamp: Hashable, Sendable {
    public var low: SIMD4<Float>
    public var mid: SIMD4<Float>
    public var high: SIMD4<Float>
    public var lowValue: Float
    public var midValue: Float
    public var highValue: Float

    public init(low: SIMD4<Float>, mid: SIMD4<Float>, high: SIMD4<Float>, lowValue: Float, midValue: Float, highValue: Float) {
        self.low = low
        self.mid = mid
        self.high = high
        self.lowValue = lowValue
        self.midValue = midValue
        self.highValue = highValue
    }

    /// A ramp over `range` with its middle colour at the range's midpoint.
    public init(low: SIMD4<Float>, mid: SIMD4<Float>, high: SIMD4<Float>, range: ClosedRange<Float>) {
        self.init(low: low, mid: mid, high: high, lowValue: range.lowerBound, midValue: (range.lowerBound + range.upperBound) / 2,
                  highValue: range.upperBound)
    }

    /// The colour of `value`. A value that is not a number takes the middle colour; two stops at one value (a ramp over a
    /// range of nothing) take the further colour, never a division by zero.
    public func color(at value: Float) -> SIMD4<Float> {
        guard value.isFinite else { return mid }
        if value <= midValue {
            let span = midValue - lowValue
            let t = span > 0 ? min(max((value - lowValue) / span, 0), 1) : 1
            return low + (mid - low) * t
        }
        let span = highValue - midValue
        let t = span > 0 ? min(max((value - midValue) / span, 0), 1) : 1
        return mid + (high - mid) * t
    }
}
