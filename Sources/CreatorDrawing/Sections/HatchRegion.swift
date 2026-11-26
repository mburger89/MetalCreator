import CreatorGeometry
import CreatorKernel

/// The part of a section view's model plane one cut hatches (R5): along `axis` (x when the line reads horizontally), from `low` to
/// `high`, either open.
public struct HatchBand: Hashable, Sendable {
    public var axis: AlignmentAxis
    public var low: Double?
    public var high: Double?

    public init(axis: AlignmentAxis, low: Double?, high: Double?) {
        self.axis = axis
        self.low = low
        self.high = high
    }

    /// One band per cut of `cutter`, in order: the first open on the first point's side, the last on the last point's, a straight
    /// line's one band open both ways.
    public static func bands(for cutter: SectionCutter) -> [HatchBand] {
        let points = cutter.points
        guard points.count >= 2 else { return [] }
        let direction = cutter.direction
        let axis: AlignmentAxis = abs(direction.x) >= abs(direction.y) ? .horizontal : .vertical
        let right = cutter.frame.right, up = cutter.frame.up
        let along = right * direction.x + up * direction.y
        let sign: Double = (axis == .horizontal ? direction.x : direction.y) < 0 ? -1 : 1
        let tPrime = along * sign
        let positions = points.map { (right * $0.x + up * $0.y).dot(tPrime) }
        let cuts = cutter.cutIndices
        return cuts.enumerated().map { order, k in
            let a = positions[k], b = positions[k + 1]
            var band = HatchBand(axis: axis, low: min(a, b), high: max(a, b))
            if order == 0 {
                if a <= b { band.low = nil } else { band.high = nil }
            }
            if order == cuts.count - 1 {
                if b <= a { band.low = nil } else { band.high = nil }
            }
            return band
        }
    }
}

/// One cut face of a part: closed polylines in the section view's model plane (even-odd, any order, holes among them), the band of
/// the cut that made it.
public struct HatchRegion: Hashable, Sendable {
    public var part: Int
    public var edges: [[Vector2]]
    public var band: HatchBand?

    public init(part: Int, edges: [[Vector2]], band: HatchBand? = nil) {
        self.part = part
        self.edges = edges
        self.band = band
    }
}

/// A circle, in the model plane, that hatch is cut to (R8).
public struct HatchClip: Hashable, Sendable {
    public var center: Vector2
    public var radius: Double

    public init(center: Vector2, radius: Double) {
        self.center = center
        self.radius = radius
    }
}
