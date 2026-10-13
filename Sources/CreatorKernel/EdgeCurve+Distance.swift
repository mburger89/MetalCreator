import CreatorGeometry
import Foundation

extension EdgeCurve {
    /// The distance from `point` to this edge: to the nearest point of a straight edge (an end, past it), or of an arc
    /// (straight to the circle where the point's angle about the axis is within the sweep, else to the nearer end). Moved
    /// here from Cull by Region so the Fake kernel and the nodes measure alike.
    public func distance(from point: Vector3) -> Double {
        switch self {
        case .line(let start, let end):
            let direction = end - start
            let lengthSquared = direction.dot(direction)
            guard lengthSquared > 0 else { return (point - start).length }
            let along = min(1, max(0, (point - start).dot(direction) / lengthSquared))
            return (point - (start + direction * along)).length
        case .circle(let center, let axis, let radius, let start, let sweep):
            return Self.distance(from: point, toCircle: center, axis: axis, radius: radius, start: start, sweep: sweep)
        }
    }

    private static func distance(from point: Vector3, toCircle center: Vector3, axis: Vector3, radius: Double, start: Vector3,
                                 sweep: Double) -> Double {
        guard let normal = axis.normalized, let first = (start - center).normalized else { return (point - center).length }
        let second = normal.cross(first)
        // `angle <= sweep` below assumes a positive (counter-clockwise) sweep, as OCCT reports it (cocct.h).
        assert(sweep >= 0, "arc sweep must be counter-clockwise positive")
        let offset = point - center
        let height = offset.dot(normal)
        let (x, y) = (offset.dot(first), offset.dot(second))
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * .pi }
        if sweep >= 2 * .pi - 1e-9 || angle <= sweep {
            let across = (x * x + y * y).squareRoot() - radius
            return (height * height + across * across).squareRoot()
        }
        let end = center + first * (radius * cos(sweep)) + second * (radius * sin(sweep))
        return min((point - start).length, (point - end).length)
    }
}
