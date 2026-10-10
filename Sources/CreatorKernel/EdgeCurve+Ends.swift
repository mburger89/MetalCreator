import CreatorGeometry
import Foundation

extension EdgeCurve {
    /// The edge's two end points; none for a full circle, which is closed.
    public var ends: [Vector3] {
        switch self {
        case .line(let start, let end):
            return [start, end]
        case .circle(let center, let axis, _, let start, let sweep):
            guard abs(sweep) < 2 * .pi - 1e-9, let k = axis.normalized else { return [] }
            // Rodrigues' rotation of the radius vector about the axis by the sweep.
            let v = start - center
            let rotated = v * cos(sweep) + k.cross(v) * sin(sweep) + k * (k.dot(v) * (1 - cos(sweep)))
            return [start, center + rotated]
        }
    }

    /// For each of `ends`, the unit direction in which the edge leaves that end (into the edge). Two edges that
    /// meet at a point continue each other when they leave it in opposite directions. Empty when the ends aren't
    /// known or the curve is degenerate.
    public var endDirections: [Vector3] {
        switch self {
        case .line(let start, let end):
            guard let along = (end - start).normalized else { return [] }
            return [along, -along]
        case .circle(let center, let axis, _, let start, let sweep):
            let points = ends
            guard points.count == 2, let k = axis.normalized,
                  let first = k.cross(start - center).normalized, let last = k.cross(points[1] - center).normalized else { return [] }
            // Counter-clockwise about the axis for a positive sweep, clockwise for a negative one.
            let travel = sweep < 0 ? -1.0 : 1.0
            return [first * travel, -last * travel]
        }
    }
}
