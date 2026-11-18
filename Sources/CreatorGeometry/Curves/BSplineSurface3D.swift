/// A B-spline surface in model space (NURBS spec, NS-3): the control net `poles`, optional rational `weights`, and each
/// direction's distinct knots with their multiplicities. Pure data; a kernel builds its own surface from it.
///
/// `poles` and `weights` are row-major, `poles[i * vCount + j]` with `i` along u (0..<uCount) and `j` along v. A direction
/// that is periodic holds its unique poles only (the knots wrap), as OpenCascade does.
public struct BSplineSurface3D: Hashable, Sendable, Codable {
    public var degreeU: Int
    public var degreeV: Int
    public var uCount: Int
    public var vCount: Int
    public var poles: [Vector3]
    public var weights: [Double]?
    public var knotsU: [Double]
    public var multiplicitiesU: [Int]
    public var knotsV: [Double]
    public var multiplicitiesV: [Int]
    public var isPeriodicU: Bool
    public var isPeriodicV: Bool

    public init(degreeU: Int, degreeV: Int, uCount: Int, vCount: Int, poles: [Vector3], weights: [Double]? = nil,
                knotsU: [Double], multiplicitiesU: [Int], knotsV: [Double], multiplicitiesV: [Int],
                isPeriodicU: Bool = false, isPeriodicV: Bool = false) {
        self.degreeU = degreeU
        self.degreeV = degreeV
        self.uCount = uCount
        self.vCount = vCount
        self.poles = poles
        self.weights = weights
        self.knotsU = knotsU
        self.multiplicitiesU = multiplicitiesU
        self.knotsV = knotsV
        self.multiplicitiesV = multiplicitiesV
        self.isPeriodicU = isPeriodicU
        self.isPeriodicV = isPeriodicV
    }

    /// The pole at `(i, j)`. Call only with `i` below `uCount` and `j` below `vCount`.
    public func pole(_ i: Int, _ j: Int) -> Vector3 { poles[i * vCount + j] }

    /// Whether the net and knots describe one B-spline surface: degrees 1 or more, at least two poles each way (a periodic
    /// direction needs the degree's worth), finite numbers, increasing knots, and in each direction multiplicities that
    /// sum to the poles plus the degree plus one (a periodic direction: every one from 1 to the degree, the first equal to the
    /// last, all but the last summing to the poles), a clamped direction's ends at degree + 1 and every interior one from 1 to
    /// the degree.
    public var isWellFormed: Bool {
        guard degreeU >= 1, degreeV >= 1, uCount >= 2, vCount >= 2, poles.count == uCount * vCount,
              poles.allSatisfy(\.isFinite) else { return false }
        guard Self.isWellFormed(degree: degreeU, count: uCount, knots: knotsU, multiplicities: multiplicitiesU,
                                periodic: isPeriodicU),
              Self.isWellFormed(degree: degreeV, count: vCount, knots: knotsV, multiplicities: multiplicitiesV,
                                periodic: isPeriodicV) else { return false }
        if let weights {
            return weights.count == poles.count && weights.allSatisfy { $0.isFinite && $0 > 0 }
        }
        return true
    }

    private static func isWellFormed(degree: Int, count: Int, knots: [Double], multiplicities: [Int],
                                     periodic: Bool) -> Bool {
        guard knots.count >= 2, knots.count == multiplicities.count, knots.allSatisfy(\.isFinite),
              zip(knots, knots.dropFirst()).allSatisfy({ $0 < $1 }) else { return false }
        if periodic {
            return multiplicities.allSatisfy { (1...degree).contains($0) } && multiplicities.first == multiplicities.last
                && multiplicities.dropLast().reduce(0, +) == count
        }
        return multiplicities.first == degree + 1 && multiplicities.last == degree + 1
            && multiplicities.dropFirst().dropLast().allSatisfy { (1...degree).contains($0) }
            && multiplicities.reduce(0, +) == count + degree + 1
    }
}
