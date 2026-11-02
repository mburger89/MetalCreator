/// The cross-section of a fillet (G2 surfacing spec, G-b).
public enum FilletProfile: Hashable, Sendable {
    /// A circular arc: tangent (G1) to both faces.
    case circular
    /// A quintic section that also matches the faces' curvature (G2) along its springs. `weight` scales the section's end
    /// tangent lengths against the circle's (1 is close to the circle's proportions).
    case curvatureContinuous(weight: Double)

    /// Every kernel's refusal of a tangency weight that is not a positive number.
    public func validate() throws {
        if case .curvatureContinuous(let weight) = self, !(weight.isFinite && weight > 0) { throw KernelError.weightNotPositive }
    }
}

/// A fillet and what it could not make smooth.
public struct FilletResult: Sendable {
    public var solid: Solid
    /// Corners where three or more fillets meet that stayed tangent only (G1) in a curvature-continuous fillet.
    public var tangentOnlyCorners: Int
    /// Joins between two strips of a chain that kink, where a curvature-continuous fillet is tangent only (G1).
    public var tangentOnlyJoins: Int

    public init(solid: Solid, tangentOnlyCorners: Int = 0, tangentOnlyJoins: Int = 0) {
        self.solid = solid
        self.tangentOnlyCorners = tangentOnlyCorners
        self.tangentOnlyJoins = tangentOnlyJoins
    }
}
