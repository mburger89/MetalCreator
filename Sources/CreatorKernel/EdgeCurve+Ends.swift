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
}
