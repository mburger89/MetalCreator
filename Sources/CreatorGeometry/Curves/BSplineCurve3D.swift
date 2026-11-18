/// A clamped B-spline in model space: `poles`, optional rational `weights`, distinct `knots` and each knot's multiplicity
/// (NURBS spec). Pure data; a kernel builds its own curve from it.
///
/// A periodic spline (`isPeriodic`, a closed curve that is smooth at its join) holds its unique poles only, with the knots and
/// multiplicities of one period as OpenCascade keeps them; `startPoint` and `endPoint` mean nothing for it.
public struct BSplineCurve3D: Hashable, Sendable, Codable {
    public var degree: Int
    public var poles: [Vector3]
    public var weights: [Double]?
    public var knots: [Double]
    public var multiplicities: [Int]
    public var isPeriodic: Bool

    public init(degree: Int, poles: [Vector3], weights: [Double]? = nil, knots: [Double], multiplicities: [Int],
                isPeriodic: Bool = false) {
        self.isPeriodic = isPeriodic
        self.degree = degree
        self.poles = poles
        self.weights = weights
        self.knots = knots
        self.multiplicities = multiplicities
    }

    /// Whether the poles, weights, knots and multiplicities describe one B-spline: degree 1 or more, two poles or
    /// more, finite numbers, increasing knots, and either (clamped) the end multiplicities degree + 1 (so the first and last
    /// poles are its ends), the interior ones from 1 to degree, and all summing to poles + degree + 1, or (`isPeriodic`) every
    /// multiplicity from 1 to degree and the first equal to the last, with all but the last summing to the poles.
    public var isWellFormed: Bool {
        guard degree >= 1, poles.count >= 2, poles.allSatisfy(\.isFinite),
              knots.count >= 2, knots.count == multiplicities.count, knots.allSatisfy(\.isFinite),
              zip(knots, knots.dropFirst()).allSatisfy({ $0 < $1 }) else { return false }
        if isPeriodic {
            guard multiplicities.allSatisfy({ (1...degree).contains($0) }), multiplicities.first == multiplicities.last,
                  multiplicities.dropLast().reduce(0, +) == poles.count else { return false }
        } else {
            guard multiplicities.first == degree + 1, multiplicities.last == degree + 1,
                  multiplicities.dropFirst().dropLast().allSatisfy({ (1...degree).contains($0) }),
                  multiplicities.reduce(0, +) == poles.count + degree + 1 else { return false }
        }
        if let weights {
            return weights.count == poles.count && weights.allSatisfy { $0.isFinite && $0 > 0 }
        }
        return true
    }

    /// The first pole, the curve's start when it is clamped (not `isPeriodic`). Call only on a well-formed spline (`isWellFormed`);
    /// a kernel refuses the others before it asks.
    public var startPoint: Vector3 { poles[0] }
    /// The last pole. Call only on a well-formed spline (`isWellFormed`).
    public var endPoint: Vector3 { poles[poles.count - 1] }
}

extension BSplineCurve3D {
    private enum CodingKeys: String, CodingKey { case degree, poles, weights, knots, multiplicities, isPeriodic }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(degree: try container.decode(Int.self, forKey: .degree), poles: try container.decode([Vector3].self, forKey: .poles),
                  weights: try container.decodeIfPresent([Double].self, forKey: .weights),
                  knots: try container.decode([Double].self, forKey: .knots),
                  multiplicities: try container.decode([Int].self, forKey: .multiplicities),
                  isPeriodic: try container.decodeIfPresent(Bool.self, forKey: .isPeriodic) ?? false)
    }

    /// `isPeriodic` is written only when set, so a clamped spline encodes as it always did.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(degree, forKey: .degree)
        try container.encode(poles, forKey: .poles)
        try container.encodeIfPresent(weights, forKey: .weights)
        try container.encode(knots, forKey: .knots)
        try container.encode(multiplicities, forKey: .multiplicities)
        if isPeriodic { try container.encode(true, forKey: .isPeriodic) }
    }
}
