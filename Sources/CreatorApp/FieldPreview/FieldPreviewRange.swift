import CreatorStyle
import CreatorViewport

/// The values the ramp's three colours stand at (fields spec §6, "Ramp and legend"). Automatic is the sampled minimum to
/// maximum with the middle halfway; a signed distance centres the middle on 0 (symmetric, so 0 is the neutral colour); "0…1"
/// fixes it to 0, 0.5, 1.
struct FieldPreviewRange: Equatable, Sendable {
    var low: Double
    var mid: Double
    var high: Double

    static let unit = FieldPreviewRange(low: 0, mid: 0.5, high: 1)

    /// The range for what was sampled: `extent` is the smallest and largest finite value (`nil` when none was finite).
    /// `nil` when there is no range to show; the fixed 0…1 range needs no values.
    static func make(extent: ClosedRange<Double>?, centredOnZero: Bool, fixedToUnit: Bool) -> FieldPreviewRange? {
        if fixedToUnit { return .unit }
        guard let extent else { return nil }
        if centredOnZero {
            let reach = max(abs(extent.lowerBound), abs(extent.upperBound))
            return reach > 0 ? FieldPreviewRange(low: -reach, mid: 0, high: reach) : FieldPreviewRange(low: -1, mid: 0, high: 1)
        }
        if extent.lowerBound == extent.upperBound {
            return FieldPreviewRange(low: extent.lowerBound - 0.5, mid: extent.lowerBound, high: extent.lowerBound + 0.5)
        }
        return FieldPreviewRange(low: extent.lowerBound, mid: (extent.lowerBound + extent.upperBound) / 2, high: extent.upperBound)
    }

    /// The viewport's ramp: the theme's three field roles at this range's three values.
    func ramp(colors: ThemeColors) -> FieldRamp {
        FieldRamp(low: colors.fieldLow.rgba, mid: colors.fieldMid.rgba, high: colors.fieldHigh.rgba, lowValue: Float(low),
                  midValue: Float(mid), highValue: Float(high))
    }
}
