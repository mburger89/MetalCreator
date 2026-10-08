import CreatorGeometry

/// Everything one solve produces.
public struct SketchSolution: Hashable, Sendable {
    public var status: SketchSolveStatus
    /// The position of every point entity. Components that could not be satisfied keep their
    /// warm-start positions, so callers can ghost the last good geometry.
    public var points: [SketchEntityID: Vector2]
    /// The radius of every circle entity.
    public var radii: [SketchEntityID: Double]
    /// Freedom of every entity.
    public var freedom: [SketchEntityID: EntityFreedom]
    /// One plain-language sentence per conflict set, for example
    /// "Horizontal on Line 3 conflicts with Angle d4 (30°)."
    public var conflictMessages: [String]
    /// Constraints and dimensions skipped because they touch a suspended projected edge.
    public var suspended: [SketchConstraintRef]
    /// The measured value of every reference (non-driving) dimension, in mm or degrees.
    public var measurements: [DimensionID: Double]

    /// The total degrees of freedom left (0 unless `.underConstrained`).
    public var degreesOfFreedom: Int {
        if case .underConstrained(let dof) = status { return dof }
        return 0
    }
}
