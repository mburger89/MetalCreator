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

    public var startPoint: Vector3 { poles[0] }
    public var endPoint: Vector3 { poles[poles.count - 1] }
}
