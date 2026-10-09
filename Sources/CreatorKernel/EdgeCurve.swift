import CreatorGeometry

/// The exact shape of a line or circle edge, which the Sketch node reads to project model edges
/// into a sketch (sketcher spec §7). Other curve kinds (ellipses, B-splines) carry none.
public enum EdgeCurve: Hashable, Sendable {
    /// A straight edge from `start` to `end`.
    case line(start: Vector3, end: Vector3)
    /// A circular edge around `center` of `radius`: from `start`, counter-clockwise about `axis` by
    /// `sweep` radians (2π for a full circle).
    case circle(center: Vector3, axis: Vector3, radius: Double, start: Vector3, sweep: Double)
}
