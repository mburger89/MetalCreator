/// The ground grid's spacing (spec §6.3): 1, 10 or 100 mm, the finest whose lines are at least
/// `minimumPoints` apart on screen. Every tenth line is a major line.
enum GridSpacing {
    static let steps: [Double] = [1, 10, 100]
    static let minimumPoints = 12.0

    static func spacing(millimetresPerPoint: Double) -> Double {
        guard millimetresPerPoint.isFinite, millimetresPerPoint > 0 else { return steps[steps.count - 1] }
        return steps.first { $0 / millimetresPerPoint >= minimumPoints } ?? steps[steps.count - 1]
    }

    /// The unit and grid label, such as "mm · grid 10 mm".
    static func label(spacing: Double) -> String {
        "mm · grid \(spacing.formatted()) mm"
    }
}
