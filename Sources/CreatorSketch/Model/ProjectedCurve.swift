import CreatorGeometry

/// The cached plane-coordinate geometry of a projected model edge.
public enum ProjectedCurve: Hashable, Sendable, Codable {
    case line(Vector2, Vector2)
    /// A counter-clockwise arc from `start` to `end` (`end > start`).
    case arc(center: Vector2, radius: Double, start: Angle, end: Angle)
    case circle(center: Vector2, radius: Double)
}
