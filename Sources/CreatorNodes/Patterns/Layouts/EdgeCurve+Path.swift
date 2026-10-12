import CreatorGeometry
import CreatorKernel
import Foundation

/// Measuring and walking a straight or circular edge's curve, for the chains Curve Pattern and Face Pattern follow.
extension EdgeCurve {
    /// A circle that goes all the way round.
    var isFullCircle: Bool {
        if case .circle(_, _, _, _, let sweep) = self { abs(sweep) >= 2 * .pi - 1e-9 } else { false }
    }

    var pathLength: Double {
        switch self {
        case .line(let start, let end): (end - start).length
        case .circle(_, _, let radius, _, let sweep): radius * abs(sweep)
        }
    }

    var startPoint: Vector3 {
        switch self {
        case .line(let start, _): start
        case .circle(_, _, _, let start, _): start
        }
    }

    var endPoint: Vector3 {
        switch self {
        case .line(_, let end): end
        case .circle(let center, let axis, _, let start, let sweep): center + Self.turned(start - center, about: axis, by: sweep)
        }
    }

    /// The same curve run the other way.
    var reversed: EdgeCurve {
        switch self {
        case .line(let start, let end): .line(start: end, end: start)
        case .circle(let center, let axis, let radius, _, let sweep):
            .circle(center: center, axis: axis, radius: radius, start: endPoint, sweep: -sweep)
        }
    }

    /// The point `distance` along from the start and the unit direction of travel there.
    func sample(at distance: Double) -> (point: Vector3, tangent: Vector3)? {
        switch self {
        case .line(let start, let end):
            guard let along = (end - start).normalized else { return nil }
            return (start + along * distance, along)
        case .circle(let center, let axis, let radius, let start, let sweep):
            guard radius > 0, sweep != 0, let k = axis.normalized else { return nil }
            let radial = Self.turned(start - center, about: k, by: sweep * distance / pathLength)
            guard let tangent = k.cross(radial).normalized else { return nil }
            return (center + radial, sweep < 0 ? -tangent : tangent)
        }
    }

    /// `vector` turned counter-clockwise about the unit-or-not `axis` by `angle` radians (Rodrigues' rotation).
    private static func turned(_ vector: Vector3, about axis: Vector3, by angle: Double) -> Vector3 {
        guard let k = axis.normalized else { return vector }
        return vector * cos(angle) + k.cross(vector) * sin(angle) + k * (k.dot(vector) * (1 - cos(angle)))
    }
}
