/// Where a dimension's line sits relative to the geometry it measures.
public enum DimensionPlacement: Sendable, Hashable {
    /// The style's standoff from the geometry, in screen points.
    case standoff
    /// The dimension line, leader end or arc passes through this world point.
    case through(Vector3)
}
