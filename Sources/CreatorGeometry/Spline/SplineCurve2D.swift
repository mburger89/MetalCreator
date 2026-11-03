import Foundation

/// An exact degree-5 clamped B-spline in plane coordinates (sketch splines spec, "The curve"): `poles`, distinct `knots` and
/// each knot's multiplicity. What `SplineDefinition.curve()` makes has interior knots of multiplicity 3 (curvature continuous),
/// but any clamped degree-5 curve with consistent counts is valid, and this is what the kernel builds its edge from.
public struct SplineCurve2D: Hashable, Sendable {
    public static let degree = 5
    /// How many points per knot interval `polyline()` samples, for consumers that want a polyline (fills, point tests).
    public static let samplesPerSpan = 16

    public var poles: [Vector2]
    public var knots: [Double]
    public var multiplicities: [Int]

    public init(poles: [Vector2], knots: [Double], multiplicities: [Int]) {
        self.poles = poles
        self.knots = knots
        self.multiplicities = multiplicities
    }

    public var degree: Int { Self.degree }

    public var parameterRange: ClosedRange<Double> { (knots.first ?? 0)...(knots.last ?? 0) }

    /// Whether the counts agree: poles = sum of multiplicities − 6, clamped ends, increasing knots, finite poles.
    public var isValid: Bool {
        knots.count >= 2 && knots.count == multiplicities.count
            && multiplicities.first == Self.degree + 1 && multiplicities.last == Self.degree + 1
            && multiplicities.dropFirst().dropLast().allSatisfy { (1...Self.degree).contains($0) }
            && zip(knots, knots.dropFirst()).allSatisfy { $0 < $1 }
            && poles.count == multiplicities.reduce(0, +) - Self.degree - 1 && poles.allSatisfy(\.isFinite)
    }

    /// The knot vector written out, each knot repeated by its multiplicity.
    var expandedKnots: [Double] { zip(knots, multiplicities).flatMap { Array(repeating: $0, count: $1) } }

    var data: BSplineData { BSplineData(degree: Self.degree, poles: poles, knots: expandedKnots) }

    public var startPoint: Vector2 { poles[0] }
    public var endPoint: Vector2 { poles[poles.count - 1] }
}

/// A B-spline over its expanded knot vector: de Boor evaluation, the derivative curve and knot insertion.
struct BSplineData {
    var degree: Int
    var poles: [Vector2]
    var knots: [Double]

    /// The index `k` with `knots[k] <= u < knots[k + 1]` among the non-empty intervals (the last one for `u` at the end).
    func span(of u: Double) -> Int {
        let last = poles.count - 1
        if u >= knots[last + 1] { return last }
        var low = degree
        var high = last + 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if u < knots[mid] { high = mid } else { low = mid }
        }
        return low
    }

    func point(at u: Double) -> Vector2 {
        guard degree > 0 else { return poles[0] }
        let k = span(of: u)
        var d = Array(poles[(k - degree)...k])
        for r in 1...degree {
            for j in stride(from: degree, through: r, by: -1) {
                let left = knots[j + k - degree]
                let alpha = (u - left) / (knots[j + 1 + k - r] - left)
                d[j] = d[j - 1] * (1 - alpha) + d[j] * alpha
            }
        }
        return d[degree]
    }

    /// The first derivative as a B-spline of one degree lower.
    var derivative: BSplineData {
        guard degree > 0 else { return BSplineData(degree: 0, poles: [.zero], knots: knots) }
        let q = (0..<(poles.count - 1)).map { i -> Vector2 in
            let width = knots[i + degree + 1] - knots[i + 1]
            return width > 0 ? (poles[i + 1] - poles[i]) * (Double(degree) / width) : .zero
        }
        return BSplineData(degree: degree - 1, poles: q, knots: Array(knots[1..<(knots.count - 1)]))
    }

    /// Inserts `u` once (Boehm); `u` must lie strictly inside the knot range and appear fewer than `degree` times.
    func inserting(_ u: Double) -> BSplineData {
        let k = span(of: u)
        var q = [poles[0]]
        for i in 1..<poles.count {
            if i <= k - degree {
                q.append(poles[i])
            } else if i <= k {
                let alpha = (u - knots[i]) / (knots[i + degree] - knots[i])
                q.append(poles[i - 1] * (1 - alpha) + poles[i] * alpha)
            } else {
                q.append(poles[i - 1])
            }
        }
        q.append(poles[poles.count - 1])
        var t = knots
        t.insert(u, at: k + 1)
        return BSplineData(degree: degree, poles: q, knots: t)
    }
}
