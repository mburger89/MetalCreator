import CreatorGeometry
import CreatorSketch

/// How a distance between two points is measured, chosen by where its label is placed (spec §4.4).
enum LinearOrientation: Hashable, Sendable {
    case aligned, horizontal, vertical

    /// Two points closer than this along an axis are already aligned with it.
    private static let axisTolerance = 1e-6

    /// For `a`, `b` and the label `q`: horizontal when `q` is within the points' x range but outside their y range, vertical
    /// for the reverse, otherwise aligned. Points already on a horizontal or vertical line stay aligned.
    static func chosen(from a: Vector2, to b: Vector2, label q: Vector2) -> LinearOrientation {
        guard abs(a.x - b.x) >= axisTolerance, abs(a.y - b.y) >= axisTolerance else { return .aligned }
        let insideX = (min(a.x, b.x)...max(a.x, b.x)).contains(q.x)
        let insideY = (min(a.y, b.y)...max(a.y, b.y)).contains(q.y)
        if insideX && !insideY { return .horizontal }
        if insideY && !insideX { return .vertical }
        return .aligned
    }

    /// `aligned` (a distance or centre distance) measured this way.
    func kind(of aligned: DimensionKind) -> DimensionKind {
        switch (self, aligned) {
        case (.horizontal, .distance(let a, let b)), (.horizontal, .centreDistance(let a, let b)): .horizontalDistance(a, b)
        case (.vertical, .distance(let a, let b)), (.vertical, .centreDistance(let a, let b)): .verticalDistance(a, b)
        default: aligned
        }
    }
}
