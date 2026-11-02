import CreatorGeometry
import Foundation

/// Intersections involving a spline: Bézier-hull style subdivision (boxes of the pieces' poles, arcs' exact boxes) down to small
/// pieces, then a damped Newton on `a(s) = b(t)` from each surviving pair, to the module's tolerance, de-duplicated.
extension CurveIntersection {
    /// Pieces smaller than this (their box's diagonal, mm) are handed to Newton.
    private static let leafSize = 0.02
    /// A cap on surviving pairs, so overlapping curves (a straight spline along a line) stay bounded; their ends are found anyway.
    private static let maximumLeaves = 4_000
    /// Roots closer than this are one: a tangential touch is a double root, which Newton reaches to within its residual
    /// tolerance on either side of the true point (a few 1e-5 mm).
    private static let mergeDistance = 5e-4

    private struct Box {
        var low: Vector2
        var high: Vector2

        var diagonal: Double { (high - low).length }

        func overlaps(_ other: Box, slack: Double) -> Bool {
            low.x <= other.high.x + slack && other.low.x <= high.x + slack
                && low.y <= other.high.y + slack && other.low.y <= high.y + slack
        }

        init(_ points: [Vector2]) {
            low = Vector2(points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0)
            high = Vector2(points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
        }
    }

    /// A piece of a base shape: the piece itself, its interval in the base's parameter, and its box.
    private struct Piece {
        var shape: CurveShape
        var from: Double
        var to: Double
        var box: Box

        init(_ shape: CurveShape, from: Double, to: Double) {
            self.shape = shape
            self.from = from
            self.to = to
            box = Box(Self.hull(of: shape))
        }

        /// Points whose convex hull holds the piece.
        private static func hull(of shape: CurveShape) -> [Vector2] {
            switch shape {
            case .line(let a, let b):
                return [a, b]
            case .spline(let curve):
                return curve.poles
            case .arc(let center, let radius, let start, let sweep):
                var points = [shape.startPoint, shape.endPoint]
                // Axis extremes inside the sweep.
                for quarter in 0..<4 {
                    let angle = Double(quarter) * .pi / 2
                    let relative = SketchMath.wrapped(angle - start)
                    if relative <= sweep { points.append(center + Vector2(cos(angle), sin(angle)) * radius) }
                }
                return points
            }
        }

        var middle: Double { (from + to) / 2 }

        /// The two halves, split at the middle of the base interval.
        func halves() -> (Piece, Piece) {
            let end = shape.parameterEnd
            let half = end / 2
            let first = Piece(shape.piece(from: 0, to: half), from: from, to: middle)
            return (first, Piece(shape.piece(from: half, to: end), from: middle, to: to))
        }
    }

    /// The spans a spline is first cut into, so a piece's poles hug one polynomial piece.
    private static func initialPieces(_ shape: CurveShape) -> [Piece] {
        guard case .spline(let curve) = shape else { return [Piece(shape, from: 0, to: shape.parameterEnd)] }
        let origin = curve.parameterRange.lowerBound
        let cuts = curve.knots.map { $0 - origin }
        return zip(cuts, cuts.dropFirst()).filter { $1 > $0 }.map { Piece(shape.piece(from: $0, to: $1), from: $0, to: $1) }
    }

    /// The points where `a` and `b` meet, at least one of them a spline.
    static func splineCrossings(_ a: CurveShape, _ b: CurveShape) -> [Vector2] {
        var seeds: [(Double, Double)] = []
        var leaves = 0
        func descend(_ p: Piece, _ q: Piece, _ depth: Int = 0) {
            guard leaves < maximumLeaves, p.box.overlaps(q.box, slack: 1e-9) else { return }
            if depth > 60 { return }
            if p.box.diagonal <= leafSize, q.box.diagonal <= leafSize {
                leaves += 1
                seeds.append((p.middle, q.middle))
            } else if p.box.diagonal >= q.box.diagonal {
                let (left, right) = p.halves()
                descend(left, q, depth + 1)
                descend(right, q, depth + 1)
            } else {
                let (left, right) = q.halves()
                descend(p, left, depth + 1)
                descend(p, right, depth + 1)
            }
        }
        for p in initialPieces(a) {
            for q in initialPieces(b) { descend(p, q) }
        }
        var found: [Vector2] = []
        for (s, t) in seeds {
            guard let point = refine(a, b, s, t) else { continue }
            if !found.contains(where: { ($0 - point).length <= mergeDistance }) { found.append(point) }
        }
        return found
    }

    /// The self-crossings of a spline: points where two parameters that are not neighbours give the same point.
    static func selfCrossings(of shape: CurveShape) -> [Vector2] {
        let spans = initialPieces(shape)
        var seeds: [(Double, Double)] = []
        var leaves = 0
        func descend(_ p: Piece, _ q: Piece, _ depth: Int = 0) {
            guard leaves < maximumLeaves, depth <= 60, p.box.overlaps(q.box, slack: 1e-9) else { return }
            let small = p.box.diagonal <= leafSize && q.box.diagonal <= leafSize
            if small {
                leaves += 1
                if abs(p.middle - q.middle) > 1e-6 { seeds.append((p.middle, q.middle)) }
            } else if p.box.diagonal >= q.box.diagonal {
                let (left, right) = p.halves()
                descend(left, q, depth + 1)
                descend(right, q, depth + 1)
            } else {
                let (left, right) = q.halves()
                descend(p, left, depth + 1)
                descend(p, right, depth + 1)
            }
        }
        for (index, p) in spans.enumerated() {
            // Halves of one span meet each other; later spans are paired whole.
            let (left, right) = p.halves()
            descend(left, right)
            for q in spans.dropFirst(index + 1) { descend(p, q) }
        }
        var found: [Vector2] = []
        for (s, t) in seeds {
            guard let (u, v, point) = refineSelf(shape, s, t), abs(u - v) > 1e-4 else { continue }
            if !found.contains(where: { ($0 - point).length <= mergeDistance }) { found.append(point) }
        }
        return found
    }

    /// Damped Gauss–Newton on `a(s) - b(t)`; nil when it does not reach the tolerance.
    private static func refine(_ a: CurveShape, _ b: CurveShape, _ s0: Double, _ t0: Double) -> Vector2? {
        guard let (_, _, point) = solve(a, b, s0, t0) else { return nil }
        return point
    }

    private static func refineSelf(_ shape: CurveShape, _ s: Double, _ t: Double) -> (Double, Double, Vector2)? {
        solve(shape, shape, s, t)
    }

    private static func solve(_ a: CurveShape, _ b: CurveShape, _ s0: Double, _ t0: Double) -> (Double, Double, Vector2)? {
        var (s, t) = (s0, t0)
        var damping = 1e-9
        func residual(_ s: Double, _ t: Double) -> Vector2 { a.point(at: s) - b.point(at: t) }
        var current = residual(s, t)
        for _ in 0..<80 {
            if current.length <= 1e-11 { break }
            let (da, db) = (a.derivative(at: s), b.derivative(at: t))
            // J = [da, -db]; solve (JᵀJ + λI) δ = -Jᵀ r.
            let (m00, m01, m11) = (SketchMath.dot(da, da), -SketchMath.dot(da, db), SketchMath.dot(db, db))
            let (g0, g1) = (SketchMath.dot(da, current), -SketchMath.dot(db, current))
            var improved = false
            while damping < 1e12 {
                let (d00, d11) = (m00 + damping * max(1, m00), m11 + damping * max(1, m11))
                let det = d00 * d11 - m01 * m01
                guard abs(det) > 1e-300 else { damping *= 10; continue }
                let ds = -(d11 * g0 - m01 * g1) / det
                let dt = -(-m01 * g0 + d00 * g1) / det
                let (ns, nt) = (min(max(s + ds, 0), a.parameterEnd), min(max(t + dt, 0), b.parameterEnd))
                let next = residual(ns, nt)
                if next.length < current.length {
                    (s, t, current) = (ns, nt, next)
                    damping = max(damping / 10, 1e-12)
                    improved = true
                    break
                }
                damping *= 10
            }
            if !improved { break }
        }
        guard current.length <= tolerance else { return nil }
        return (s, t, (a.point(at: s) + b.point(at: t)) * 0.5)
    }
}
