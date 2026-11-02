import CreatorGeometry
import Foundation

/// Exact area, first moments and point containment for loops of lines and arcs (Green's theorem).
enum LoopMeasure {
    /// Signed area: positive for counter-clockwise loops.
    static func area(_ loop: [LoopSegment]) -> Double {
        loop.reduce(0) { total, segment in
            switch segment.geometry {
            case .line(let p, let q):
                return total + 0.5 * (p.x * q.y - q.x * p.y)
            case .arc(let c, let r, let a, let b):
                return total + 0.5 * (r * r * (b - a) + r * (c.x * (sin(b) - sin(a)) - c.y * (cos(b) - cos(a))))
            case .spline(let curve):
                return total + 0.5 * integrate(curve) { point, velocity in point.x * velocity.y - point.y * velocity.x }
            }
        }
    }

    /// (∬x dA, ∬y dA) over the loop's interior, signed like `area`.
    static func moments(_ loop: [LoopSegment]) -> Vector2 {
        var mx = 0.0
        var my = 0.0
        for segment in loop {
            switch segment.geometry {
            case .line(let p, let q):
                let e = q - p
                mx += e.y / 2 * (p.x * p.x + p.x * e.x + e.x * e.x / 3)
                my -= e.x / 2 * (p.y * p.y + p.y * e.y + e.y * e.y / 3)
            case .arc(let c, let r, let a, let b):
                func fx(_ t: Double) -> Double {
                    c.x * c.x * sin(t) + 2 * c.x * r * (t / 2 + sin(2 * t) / 4) + r * r * (sin(t) - pow(sin(t), 3) / 3)
                }
                func fy(_ t: Double) -> Double {
                    -c.y * c.y * cos(t) + 2 * c.y * r * (t / 2 - sin(2 * t) / 4) + r * r * (-cos(t) + pow(cos(t), 3) / 3)
                }
                mx += r / 2 * (fx(b) - fx(a))
                my += r / 2 * (fy(b) - fy(a))
            case .spline(let curve):
                mx += 0.5 * integrate(curve) { point, velocity in point.x * point.x * velocity.y }
                my -= 0.5 * integrate(curve) { point, velocity in point.y * point.y * velocity.x }
            }
        }
        return Vector2(mx, my)
    }

    /// ∫ f(C(t), C′(t)) dt over a spline by Gauss–Legendre on each knot interval (the integrands are polynomial, so it is exact).
    static func integrate(_ curve: SplineCurve2D, _ f: (Vector2, Vector2) -> Double) -> Double {
        zip(curve.knots, curve.knots.dropFirst()).reduce(0) { total, span in
            total + GaussLegendre.integrate(from: span.0, to: span.1) { f(curve.point(at: $0), curve.derivative(at: $0, order: 1)) }
        }
    }

    /// Even–odd containment by a ray towards +x. Arcs are split at their top and bottom so each
    /// piece crosses a horizontal line at most once; the half-open rule (`y > p.y`) counts a
    /// vertex on the ray once.
    static func contains(_ loop: [LoopSegment], _ p: Vector2) -> Bool {
        var crossings = 0
        func count(_ a: Vector2, _ b: Vector2, x: () -> Double) {
            if (a.y > p.y) != (b.y > p.y), x() > p.x { crossings += 1 }
        }
        for segment in loop {
            switch segment.geometry {
            case .line(let a, let b):
                count(a, b) { a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y) }
            case .arc(let c, let r, let from, let to):
                let (lo, hi) = (min(from, to), max(from, to))
                var cuts = [lo]
                var k = ((lo - .pi / 2) / .pi).rounded(.down) + 1
                while .pi / 2 + k * .pi < hi {
                    cuts.append(.pi / 2 + k * .pi)
                    k += 1
                }
                cuts.append(hi)
                // The outermost ends are the exact vertices, so neighbours agree on their y.
                let (lowEnd, highEnd) = from < to ? (segment.start, segment.end) : (segment.end, segment.start)
                func point(_ t: Double) -> Vector2 {
                    t == lo ? lowEnd : t == hi ? highEnd : SketchMath.point(on: c, radius: r, at: t)
                }
                for (t0, t1) in zip(cuts, cuts.dropFirst()) {
                    let a = point(t0)
                    let b = point(t1)
                    count(a, b) {
                        let dy = p.y - c.y
                        let dx = max(0, r * r - dy * dy).squareRoot()
                        return cos((t0 + t1) / 2) >= 0 ? c.x + dx : c.x - dx
                    }
                }
            case .spline(let curve):
                // The curve sampled finely (32 per knot interval) with its true ends, so neighbours agree on a vertex's y.
                var points = [segment.start]
                for (a, b) in zip(curve.knots, curve.knots.dropFirst()) {
                    for step in 1...32 { points.append(curve.point(at: a + (b - a) * Double(step) / 32)) }
                }
                points[points.count - 1] = segment.end
                for (a, b) in zip(points, points.dropFirst()) {
                    count(a, b) { a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y) }
                }
            }
        }
        return crossings % 2 == 1
    }
}
