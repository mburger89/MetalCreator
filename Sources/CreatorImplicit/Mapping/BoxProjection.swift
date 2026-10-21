import CreatorGeometry
import Foundation

/// How far a box lies from a line, which is what a mapping needs to bound its stretch: the stretch of a cylindrical or spherical mapping
/// at a point is the mean radius over the point's distance from the axis, so the largest stretch over a region is the mean radius over
/// the box's nearest approach (implicit spec §3.5).
enum BoxProjection {
    /// The nearest and the farthest the box (grown by `LatticeMapping.margin`) comes to the line through `origin` along `zAxis`, where
    /// `xAxis` and `yAxis` complete the frame. The box seen along the line is the convex hull of its eight corners, so the nearest is
    /// the distance from the line to that polygon: 0 when the line passes through it.
    static func radialRange(of box: BoundingBox, origin: Vector3, xAxis: Vector3, yAxis: Vector3) -> (nearest: Double, farthest: Double) {
        let corners = corners(of: box)
        let flat = corners.map { Vector2(($0 - origin).dot(xAxis), ($0 - origin).dot(yAxis)) }
        return (distanceToOrigin(ofHullOf: flat), flat.map(\.length).max() ?? 0)
    }

    /// The eight corners of `box`.
    static func corners(of box: BoundingBox) -> [Vector3] {
        (0..<8).map { bit in
            Vector3(bit & 1 == 0 ? box.min.x : box.max.x, bit & 2 == 0 ? box.min.y : box.max.y, bit & 4 == 0 ? box.min.z : box.max.z)
        }
    }

    /// The distance from (0, 0) to the convex hull of `points`; 0 when it is inside or on it.
    static func distanceToOrigin(ofHullOf points: [Vector2]) -> Double {
        let hull = convexHull(points)
        guard hull.count > 1 else { return hull.first?.length ?? 0 }
        var inside = true
        var nearest = Double.infinity
        for index in hull.indices {
            let (a, b) = (hull[index], hull[(index + 1) % hull.count])
            let edge = b - a
            if edge.x * (0 - a.y) - edge.y * (0 - a.x) < -1e-12 { inside = false }
            let length2 = edge.x * edge.x + edge.y * edge.y
            let t = length2 > 0 ? min(max(-(a.x * edge.x + a.y * edge.y) / length2, 0), 1) : 0
            nearest = min(nearest, (a + edge * t).length)
        }
        return inside && hull.count > 2 ? 0 : nearest
    }

    /// Andrew's monotone chain: the hull counter-clockwise, without repeating the first point.
    static func convexHull(_ points: [Vector2]) -> [Vector2] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count > 2 else { return sorted }
        func turn(_ o: Vector2, _ a: Vector2, _ b: Vector2) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [Vector2] = []
        for point in sorted {
            while lower.count >= 2 && turn(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        var upper: [Vector2] = []
        for point in sorted.reversed() {
            while upper.count >= 2 && turn(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
