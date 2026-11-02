import Foundation

/// A fit point's two handles. `nil` is automatic (filled by the spline's own solve); a value is active and fixes the first
/// derivative (`tangent`, its direction the tangent and its length the weight) or the second (`curvature`) there, both with
/// respect to the chord-length parameter of the spline.
public struct SplineHandle: Hashable, Sendable, Codable {
    public var tangent: Vector2?
    public var curvature: Vector2?

    public init(tangent: Vector2? = nil, curvature: Vector2? = nil) {
        self.tangent = tangent
        self.curvature = curvature
    }

    public static let automatic = SplineHandle()
}

/// The first and second derivative of a spline at a fit point once its automatic handles are filled in.
public struct ResolvedSplineHandle: Hashable, Sendable {
    public var tangent: Vector2
    public var secondDerivative: Vector2

    /// Signed curvature there, `(T × A) / |T|³`; 0 where the tangent vanishes.
    public var curvature: Double {
        let speed = tangent.length
        guard speed > 0 else { return 0 }
        return (tangent.x * secondDerivative.y - tangent.y * secondDerivative.x) / (speed * speed * speed)
    }
}

/// A fit-point spline: the points and a handle for each. The curve is a pure function of this value (the automatic handles are
/// never stored), so a saved and reopened spline is the same curve.
public struct SplineDefinition: Hashable, Sendable {
    public var points: [Vector2]
    public var handles: [SplineHandle]

    /// `handles` shorter than `points` are padded with automatic handles.
    public init(points: [Vector2], handles: [SplineHandle] = []) {
        self.points = points
        self.handles = handles + Array(repeating: .automatic, count: max(0, points.count - handles.count))
    }

    /// The parameter length of each span: the chord between its fit points (never 0, so a repeated point can't collapse a span).
    public var spans: [Double] {
        zip(points, points.dropFirst()).map { max(($1 - $0).length, 1e-9) }
    }

    /// Every fit point's first and second derivative: the active handles as given and the automatic ones solved so that the
    /// third and fourth derivatives are continuous at an interior point with both handles automatic, the third at one with a
    /// single automatic handle, and (natural ends) zero at an end in the same way. The system is the same for x and y.
    public func resolvedHandles() -> [ResolvedSplineHandle] {
        precondition(points.count >= 2, "A spline needs at least two fit points.")
        let count = points.count
        // Unknown slots: (point, isCurvature) for each automatic vector.
        var slot: [[Int?]] = Array(repeating: [nil, nil], count: count)
        var unknowns = 0
        for i in 0..<count {
            for kind in 0..<2 where (kind == 0 ? handles[i].tangent : handles[i].curvature) == nil {
                slot[i][kind] = unknowns
                unknowns += 1
            }
        }
        var known = handles.map {
            ResolvedSplineHandle(tangent: $0.tangent ?? .zero, secondDerivative: $0.curvature ?? .zero)
        }
        guard unknowns > 0 else { return known }
        // Natural conditions at both ends of one span fix nothing but a parabola's worth of shape: with every handle automatic
        // the system is singular, and the spline is the straight chord.
        if count == 2, unknowns == 4 { return chordHandles(known: known) }

        var (matrix, rhs) = system(slot: slot, unknowns: unknowns, known: known)
        guard let solution = Self.solve(&matrix, &rhs) else { return chordHandles(known: known) }
        for i in 0..<count {
            if let column = slot[i][0] { known[i].tangent = solution[column] }
            if let column = slot[i][1] { known[i].secondDerivative = solution[column] }
        }
        return known
    }

    /// The matrix and right-hand side (x and y together) of the conditions on the automatic handles: one row per unknown at a
    /// point, the third derivative's join first and the fourth's second.
    private func system(slot: [[Int?]], unknowns: Int, known: [ResolvedSplineHandle]) -> ([[Double]], [Vector2]) {
        let h = spans
        var matrix = Array(repeating: Array(repeating: 0.0, count: unknowns), count: unknowns)
        var rhs = Array(repeating: Vector2.zero, count: unknowns)
        var row = 0
        // Adds `scale × functional(span)` to the current row.
        func add(_ derivative: QuinticHermite.Derivative, span: Int, scale: Double) {
            let c = QuinticHermite.coefficients(of: derivative, h: h[span])
            let data: [(point: Int, kind: Int?)] = [(span, nil), (span + 1, nil), (span, 0), (span + 1, 0), (span, 1), (span + 1, 1)]
            for (index, datum) in data.enumerated() {
                let value = scale * c[index]
                guard let kind = datum.kind else {
                    rhs[row] -= points[datum.point] * value
                    continue
                }
                if let column = slot[datum.point][kind] {
                    matrix[row][column] += value
                } else {
                    rhs[row] -= (kind == 0 ? known[datum.point].tangent : known[datum.point].secondDerivative) * value
                }
            }
        }
        for i in 0..<points.count {
            let automatic = (slot[i][0] == nil ? 0 : 1) + (slot[i][1] == nil ? 0 : 1)
            for order in 0..<automatic {
                let (third, fourth) = (QuinticHermite.Derivative.thirdAtStart, QuinticHermite.Derivative.fourthAtStart)
                if i > 0 { add(order == 0 ? .thirdAtEnd : .fourthAtEnd, span: i - 1, scale: 1) }
                if i < points.count - 1 { add(order == 0 ? third : fourth, span: i, scale: i > 0 ? -1 : 1) }
                row += 1
            }
        }
        return (matrix, rhs)
    }

    /// The fall-back for a system with no solution: each automatic tangent is the direction through its neighbours (the chord at
    /// an end) at unit speed and each automatic second derivative is 0, so a spline stays finite and straight-ish.
    private func chordHandles(known: [ResolvedSplineHandle]) -> [ResolvedSplineHandle] {
        var result = known
        for i in points.indices {
            let before = max(i - 1, 0)
            let after = min(i + 1, points.count - 1)
            let span = (points[after] - points[before])
            let length = span.length
            if handles[i].tangent == nil, length > 0 { result[i].tangent = span * (1 / length) }
            if handles[i].curvature == nil { result[i].secondDerivative = .zero }
        }
        return result
    }

    /// Dense Gaussian elimination with partial pivoting and row scaling; the rows are few (twice the fit points at most). `nil`
    /// for a singular system.
    private static func solve(_ a: inout [[Double]], _ b: inout [Vector2]) -> [Vector2]? {
        let n = a.count
        for r in 0..<n {
            let scale = a[r].map(abs).max() ?? 0
            guard scale > 0 else { continue }
            a[r] = a[r].map { $0 / scale }
            b[r] *= 1 / scale
        }
        for column in 0..<n {
            var pivot = column
            for r in column..<n where abs(a[r][column]) > abs(a[pivot][column]) { pivot = r }
            guard abs(a[pivot][column]) > 1e-12 else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for r in (column + 1)..<max(n, column + 1) {
                let factor = a[r][column] / a[column][column]
                guard factor != 0 else { continue }
                for c in column..<n { a[r][c] -= factor * a[column][c] }
                b[r] -= b[column] * factor
            }
        }
        var x = Array(repeating: Vector2.zero, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[r]
            for c in (r + 1)..<max(n, r + 1) { sum -= x[c] * a[r][c] }
            x[r] = sum * (1 / a[r][r])
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }

    /// The exact curve as a degree-5 B-spline: each span's Hermite data becomes one Bézier, and the chain is clamped with
    /// interior knots of multiplicity 3 at the cumulative chord lengths.
    public func curve() -> SplineCurve2D {
        let resolved = resolvedHandles()
        let h = spans
        var knots = [0.0]
        for span in h { knots.append(knots[knots.count - 1] + span) }
        let beziers = h.indices.map { i in
            QuinticHermite(p0: points[i], p1: points[i + 1], t0: resolved[i].tangent, t1: resolved[i + 1].tangent,
                           a0: resolved[i].secondDerivative, a1: resolved[i + 1].secondDerivative, h: h[i]).bezier
        }
        // The B-spline's poles are blossoms of the knot vector; for this chain they are the Bézier poles B1 and B2 (extended
        // across the joint for the first, by the ratio of the neighbouring spans) and B3 of each span, then B4 and B5 of the
        // last.
        var poles = [beziers[0][0]]
        for (i, bezier) in beziers.enumerated() {
            let ratio = i == 0 ? 0 : h[i - 1] / h[i]
            poles.append(bezier[1] * (1 + ratio) - bezier[2] * ratio)
            poles.append(bezier[2])
            poles.append(bezier[3])
        }
        poles.append(beziers[beziers.count - 1][4])
        poles.append(beziers[beziers.count - 1][5])
        let multiplicities = [6] + Array(repeating: 3, count: h.count - 1) + [6]
        return SplineCurve2D(poles: poles, knots: knots, multiplicities: multiplicities)
    }
}
