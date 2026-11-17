/// A clamped B-spline in model space: `poles`, optional rational `weights`, distinct `knots` and each knot's multiplicity
/// (NURBS spec). Pure data; a kernel builds its own curve from it.
public struct BSplineCurve3D: Hashable, Sendable, Codable {
    public var degree: Int
    public var poles: [Vector3]
    public var weights: [Double]?
    public var knots: [Double]
    public var multiplicities: [Int]

    public init(degree: Int, poles: [Vector3], weights: [Double]? = nil, knots: [Double], multiplicities: [Int]) {
        self.degree = degree
        self.poles = poles
        self.weights = weights
        self.knots = knots
        self.multiplicities = multiplicities
    }

    /// Whether the poles, weights, knots and multiplicities describe one clamped-or-not B-spline: degree 1 or more, two poles or
    /// more, finite numbers, increasing knots, each multiplicity from 1 to degree + 1 and summing to poles + degree + 1.
    public var isWellFormed: Bool {
        guard degree >= 1, poles.count >= 2, poles.allSatisfy(\.isFinite),
              knots.count >= 2, knots.count == multiplicities.count, knots.allSatisfy(\.isFinite),
              zip(knots, knots.dropFirst()).allSatisfy({ $0 < $1 }),
              multiplicities.allSatisfy({ (1...(degree + 1)).contains($0) }),
              multiplicities.reduce(0, +) == poles.count + degree + 1 else { return false }
        if let weights {
            return weights.count == poles.count && weights.allSatisfy { $0.isFinite && $0 > 0 }
        }
        return true
    }

    /// The first pole. Call only on a well-formed spline (`isWellFormed`); a kernel refuses the others before it asks.
    public var startPoint: Vector3 { poles[0] }
    /// The last pole. Call only on a well-formed spline (`isWellFormed`).
    public var endPoint: Vector3 { poles[poles.count - 1] }
}
