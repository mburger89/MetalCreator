import CreatorGeometry

/// The warm-start value of one entity's unknowns from the last good solve.
public enum SolvedState: Hashable, Sendable, Codable {
    case point(Vector2)
    case radius(Double)
}
