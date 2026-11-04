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
        fileprivate static func hull(of shape: CurveShape) -> [Vector2] {
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

        /// The line through the piece's ends when every pole lies within `slack` of it (a line, or a spline that is straight).
        func flatChord(slack: Double) -> (Vector2, Vector2)? {
            switch shape {
            case .line(let a, let b): return (b - a).length > 0 ? (a, b) : nil
            case .arc: return nil
            case .spline: break
            }
            let (a, b) = (shape.startPoint, shape.endPoint)
            guard let unit = SketchMath.normalized(b - a) else { return nil }
            let flat = Self.hull(of: shape).allSatisfy { abs(SketchMath.cross($0 - a, unit)) <= slack }
            return flat ? (a, b) : nil
        }

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
        // The same curve twice (either way round): their crossings are only their ends, which `points` adds.
        if sameCurve(a, b) { return [] }
        var seeds: [(Double, Double)] = []
        var leaves = 0
        func descend(_ p: Piece, _ q: Piece, _ depth: Int = 0) {
            guard leaves < maximumLeaves, p.box.overlaps(q.box, slack: 1e-9) else { return }
            if depth > 60 { return }
            // Overlap is never enumerated leaf by leaf: straight pieces on one line are skipped whole (their ends are found
            // by `points` as the ends of each curve lying on the other).
            if coincidentStraight(p, q) { return }
            if p.box.diagonal <= leafSize, q.box.diagonal <= leafSize {
                leaves += 1
                if !runsAlong(p, in: b) { seeds.append((p.middle, q.middle)) }
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

    /// True when each curve's sampled points (17 along it) lie on the other within 1e-7 mm.
    private static func sameCurve(_ a: CurveShape, _ b: CurveShape) -> Bool {
        func lies(_ x: CurveShape, on y: CurveShape) -> Bool {
            (0...16).allSatisfy { step in
                let point = x.point(at: x.parameterEnd * Double(step) / 16)
                return (y.point(at: y.nearestParameter(to: point)) - point).length <= 1e-7
            }
        }
        return lies(a, on: b) && lies(b, on: a)
    }

    /// True when both pieces are straight and lie on one line.
    private static func coincidentStraight(_ p: Piece, _ q: Piece) -> Bool {
        let slack = 1e-7
        guard let (a, b) = p.flatChord(slack: slack), let (c, d) = q.flatChord(slack: slack),
              let unit = SketchMath.normalized(b - a) else { return false }
        return abs(SketchMath.cross(c - a, unit)) <= slack && abs(SketchMath.cross(d - a, unit)) <= slack
    }

    /// True when the piece `p` of one curve lies along the other curve `other` (its ends and its middle within 1e-7 mm of it,
    /// with parallel tangents): an overlap, whose crossings are not points. A tangential touch is not: it leaves the curve
    /// within a leaf's size.
    private static func runsAlong(_ p: Piece, in other: CurveShape) -> Bool {
        let samples = [p.shape.startPoint, p.shape.point(at: p.shape.parameterEnd / 2), p.shape.endPoint]
        for point in samples {
            let t = other.nearestParameter(to: point)
            guard (other.point(at: t) - point).length <= 1e-7 else { return false }
        }
        let mid = p.shape.parameterEnd / 2
        let tangent = p.shape.tangent(at: mid)
        let tangentOther = other.tangent(at: other.nearestParameter(to: p.shape.point(at: mid)))
        return abs(SketchMath.cross(tangent, tangentOther)) <= 1e-3
    }

    /// True when `q` starts where `p` ends or the other way round (the same parameter of the same curve).
    private static func isNeighbours(_ p: Piece, _ q: Piece) -> Bool {
        abs(p.to - q.from) <= 1e-12 || abs(q.to - p.from) <= 1e-12
    }

    /// True when every edge of the pieces' control polygons points within 90 degrees of one direction (the chord from the
    /// first start to the last end). A B-spline's derivative is a positive combination of those edges, so the pieces
    /// together then move steadily along that direction and never meet themselves.
    private static func isMonotone(_ pieces: Piece...) -> Bool {
        let ordered = pieces.count == 2 && pieces[1].to <= pieces[0].from + 1e-12 ? pieces.reversed() : pieces
        guard let first = ordered.first, let last = ordered.last,
              let direction = SketchMath.normalized(last.shape.endPoint - first.shape.startPoint) else { return false }
        let floor = 1e-12 * max(first.box.diagonal, last.box.diagonal)
        for piece in ordered {
            let poles = Piece.hull(of: piece.shape)
            for (a, b) in zip(poles, poles.dropFirst()) {
                let edge = b - a
                if edge.length <= floor { continue }
                if SketchMath.dot(edge, direction) <= 1e-9 * edge.length { return false }
            }
        }
        return true
    }

    /// The self-crossings of a spline: points where two parameters that are not neighbours give the same point.
    static func selfCrossings(of shape: CurveShape) -> [Vector2] {
        let spans = initialPieces(shape)
        var seeds: [(Double, Double)] = []
        var leaves = 0
        func descend(_ p: Piece, _ q: Piece, _ depth: Int = 0) {
            guard leaves < maximumLeaves, depth <= 60, p.box.overlaps(q.box, slack: 1e-9) else { return }
            // Neighbours meet at their joint, and their boxes overlap around it however finely they are cut: when the two
            // pieces together run one way (see `isMonotone`) they cannot cross, so they are not searched.
            if isNeighbours(p, q), isMonotone(p, q) { return }
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
        // Every piece's halves meet each other, down to leaf size, so a small loop inside one half is found too; later spans are
        // paired whole.
        func searchWithin(_ p: Piece, _ depth: Int = 0) {
            guard leaves < maximumLeaves, depth <= 40, p.box.diagonal > leafSize, !isMonotone(p) else { return }
            let (left, right) = p.halves()
            descend(left, right)
            searchWithin(left, depth + 1)
            searchWithin(right, depth + 1)
        }
        for (index, p) in spans.enumerated() {
            searchWithin(p)
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
