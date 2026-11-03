import CreatorGeometry

/// The warm-start value of one entity's unknowns from the last good solve.
public enum SolvedState: Hashable, Sendable, Codable {
    case point(Vector2)
    case radius(Double)
    /// A spline's active handle values, one entry per fit point: a vector where that handle is active, `nil` where it is
    /// automatic. The flags live in the entity (`SplineHandleState`); these are the values the solver last settled on.
    case splineHandles([SplineHandle])
}
