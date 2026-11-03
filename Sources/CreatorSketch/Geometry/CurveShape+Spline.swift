import CreatorGeometry
import Foundation

/// Helpers the spline case of `CurveShape` shares with the intersections and the loop measures.
extension CurveShape {
    /// The spline's curve and the parameter it starts at; a spline shape's own parameter runs from 0, so its curve's is this plus it.
    var splineParts: (curve: SplineCurve2D, origin: Double)? {
        if case .spline(let curve) = self { return (curve, curve.parameterRange.lowerBound) }
        return nil
    }

    /// The first derivative with respect to the shape's own parameter (not unit length).
    func derivative(at parameter: Double) -> Vector2 {
        switch self {
        case .line(let a, let b): b - a
        case .arc(_, let radius, let start, _): Vector2(-sin(start + parameter), cos(start + parameter)) * radius
        case .spline(let curve): curve.derivative(at: curve.parameterRange.lowerBound + parameter, order: 1)
        }
    }

    /// The signed curvature at `parameter` (left turns positive).
    func curvature(at parameter: Double) -> Double {
        if case .spline(let curve) = self { return curve.curvature(at: curve.parameterRange.lowerBound + parameter) }
        return curvature
    }

    /// The length of a spline between two of its own parameters, by Gauss–Legendre on each knot interval.
    static func splineLength(_ curve: SplineCurve2D, from t0: Double, to t1: Double) -> Double {
        let origin = curve.parameterRange.lowerBound
        let (lo, hi) = (origin + min(t0, t1), origin + max(t0, t1))
        var total = 0.0
        for (a, b) in zip(curve.knots, curve.knots.dropFirst()) {
            let (from, to) = (max(a, lo), min(b, hi))
            guard to > from else { continue }
            total += GaussLegendre.integrate(from: from, to: to) { curve.derivative(at: $0, order: 1).length }
        }
        return total
    }

    /// The piece of a spline between two of its own parameters, `0 <= t0 < t1 <= parameterEnd`.
    static func splinePiece(_ curve: SplineCurve2D, from t0: Double, to t1: Double) -> CurveShape {
        let range = curve.parameterRange
        var piece = curve
        let end = range.upperBound - range.lowerBound
        if t1 < end, let parts = piece.split(at: range.lowerBound + t1) { piece = parts.0 }
        if t0 > 0, let parts = piece.split(at: range.lowerBound + t0) { piece = parts.1 }
        return .spline(piece)
    }
}

/// Gauss–Legendre quadrature with nodes found once by Newton on the Legendre polynomial.
enum GaussLegendre {
    static let order = 12
    static let rule: [(node: Double, weight: Double)] = (0..<order).map { index in
        var x = cos(Double.pi * (Double(index) + 0.75) / (Double(order) + 0.5))
        var derivative = 1.0
        for _ in 0..<100 {
            var (p0, p1) = (1.0, x)
            for k in 2...order {
                let p2 = ((2 * Double(k) - 1) * x * p1 - (Double(k) - 1) * p0) / Double(k)
                (p0, p1) = (p1, p2)
            }
            derivative = Double(order) * (x * p1 - p0) / (x * x - 1)
            let step = p1 / derivative
            x -= step
            if abs(step) < 1e-16 { break }
        }
        return (x, 2 / ((1 - x * x) * derivative * derivative))
    }

    static func integrate(from a: Double, to b: Double, _ f: (Double) -> Double) -> Double {
        let (mid, half) = ((a + b) / 2, (b - a) / 2)
        return half * rule.reduce(0) { $0 + $1.weight * f(mid + half * $1.node) }
    }

    static func integrate(from a: Double, to b: Double, _ f: (Double) -> Vector2) -> Vector2 {
        let (mid, half) = ((a + b) / 2, (b - a) / 2)
        return rule.reduce(Vector2.zero) { $0 + f(mid + half * $1.node) * (half * $1.weight) }
    }
}
