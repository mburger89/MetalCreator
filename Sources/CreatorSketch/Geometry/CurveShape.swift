import CreatorGeometry
import Foundation

/// A curve in plane coordinates, as regions and commands see it.
enum CurveShape: Hashable, Sendable {
    case line(Vector2, Vector2)
    /// A counter-clockwise arc from polar angle `start` (radians) through `sweep` in (0, 2π].
    /// A sweep of exactly 2π is a full circle.
    case arc(center: Vector2, radius: Double, start: Double, sweep: Double)

    static let fullTurn = 2 * Double.pi

    var isFullCircle: Bool {
        if case .arc(_, _, _, let sweep) = self { return sweep >= Self.fullTurn }
        return false
    }

    /// Parameters run over [0, 1] on a line and over [0, sweep] (radians from `start`) on an arc.
    var parameterEnd: Double {
        switch self {
        case .line: 1
        case .arc(_, _, _, let sweep): sweep
        }
    }

    func point(at parameter: Double) -> Vector2 {
        switch self {
        case .line(let a, let b): a + (b - a) * parameter
        case .arc(let center, let radius, let start, _): SketchMath.point(on: center, radius: radius, at: start + parameter)
        }
    }

    var startPoint: Vector2 { point(at: 0) }
    var endPoint: Vector2 { point(at: parameterEnd) }

    /// The parameter of the point on the curve's line or circle nearest `p`: unclamped along a
    /// line, in [0, 2π) around an arc.
    func parameter(of p: Vector2) -> Double {
        switch self {
        case .line(let a, let b):
            let d = b - a
            let squared = SketchMath.dot(d, d)
            return squared > 0 ? SketchMath.dot(p - a, d) / squared : 0
        case .arc(let center, _, let start, _):
            return SketchMath.wrapped(SketchMath.angle(p - center) - start)
        }
    }

    /// The parameter, clamped to the curve, of the curve point nearest `p`.
    func nearestParameter(to p: Vector2) -> Double {
        let t = parameter(of: p)
        switch self {
        case .line:
            return min(max(t, 0), 1)
        case .arc(_, _, _, let sweep):
            if t <= sweep { return t }
            // Outside the span: the nearer end, measured around the circle.
            return (t - sweep) <= (Self.fullTurn - t) ? sweep : 0
        }
    }

    /// The length of a parameter interval, in mm.
    func length(from t0: Double, to t1: Double) -> Double {
        switch self {
        case .line(let a, let b): (b - a).length * abs(t1 - t0)
        case .arc(_, let radius, _, _): radius * abs(t1 - t0)
        }
    }

    /// True when `p` lies on the curve within `tolerance` mm.
    func contains(_ p: Vector2, tolerance: Double) -> Bool {
        switch self {
        case .line(let a, let b):
            let t = nearestParameter(to: p)
            return (point(at: t) - p).length <= tolerance && (b - a).length > 0
        case .arc(let center, let radius, _, let sweep):
            guard abs((p - center).length - radius) <= tolerance else { return false }
            if isFullCircle { return true }
            let t = parameter(of: p)
            let slack = radius > 0 ? tolerance / radius : 0
            return t <= sweep + slack || t >= Self.fullTurn - slack
        }
    }

    /// The unit tangent in the direction of increasing parameter at `parameter`.
    func tangent(at parameter: Double) -> Vector2 {
        switch self {
        case .line(let a, let b):
            return SketchMath.normalized(b - a) ?? Vector2(1, 0)
        case .arc(_, _, let start, _):
            let angle = start + parameter
            return Vector2(-sin(angle), cos(angle))
        }
    }

    /// The signed curvature in the direction of increasing parameter (left turns positive).
    var curvature: Double {
        switch self {
        case .line: 0
        case .arc(_, let radius, _, _): radius > 0 ? 1 / radius : 0
        }
    }

    /// The piece between two parameters, `t0 < t1`.
    func piece(from t0: Double, to t1: Double) -> CurveShape {
        switch self {
        case .line: .line(point(at: t0), point(at: t1))
        case .arc(let center, let radius, let start, _): .arc(center: center, radius: radius, start: start + t0, sweep: t1 - t0)
        }
    }
}
