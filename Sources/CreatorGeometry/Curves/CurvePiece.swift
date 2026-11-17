import Foundation

/// One piece of a 3D curve: a line, a circular arc or a B-spline. Pieces join end to end to make a curve.
public enum CurvePiece: Hashable, Sendable {
    case line(Vector3, Vector3)
    /// An arc about `center` in the plane whose unit normal is `normal`, from `start` (a point on the circle) through
    /// `sweep` radians, signed about `normal` (negative runs clockwise seen from the normal's tip).
    case arc(center: Vector3, normal: Vector3, radius: Double, start: Vector3, sweep: Double)
    case spline(BSplineCurve3D)

    public var start: Vector3 {
        switch self {
        case .line(let a, _): a
        case .arc(_, _, _, let start, _): start
        case .spline(let curve): curve.startPoint
        }
    }

    public var end: Vector3 {
        switch self {
        case .line(_, let b): b
        case .arc(let center, let normal, _, let start, let sweep):
            Self.rotate(start - center, about: normal, by: sweep) + center
        case .spline(let curve): curve.endPoint
        }
    }

    /// `v` turned `angle` radians about the unit axis `axis` (Rodrigues).
    public static func rotate(_ v: Vector3, about axis: Vector3, by angle: Double) -> Vector3 {
        let k = axis.normalized ?? axis
        let c = cos(angle)
        let s = sin(angle)
        return v * c + k.cross(v) * s + k * (k.dot(v) * (1 - c))
    }

    /// Every segment of a sketch or profile loop placed on `plane`, in order. An arc with `end < start` gets a negative sweep.
    public static func pieces(of segments: [Segment2D], on plane: Plane) -> [CurvePiece] {
        segments.map { segment in
            switch segment {
            case .line(let a, let b):
                return .line(plane.point(a), plane.point(b))
            case .arc(let center, let radius, let start, let end):
                return .arc(center: plane.point(center), normal: plane.normal, radius: radius,
                            start: plane.point(segment.startPoint), sweep: end.radians - start.radians)
            case .spline(let curve):
                return .spline(BSplineCurve3D(degree: curve.degree, poles: curve.poles.map { plane.point($0) },
                                              knots: curve.knots, multiplicities: curve.multiplicities))
            }
        }
    }
}
