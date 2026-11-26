import CreatorGeometry
import CreatorKernel

/// The exact model geometry an anchor holds now (3D model millimetres, never a projected polyline).
public enum AnchorGeometry: Hashable, Sendable {
    case segment(Vector3, Vector3)
    /// An arc from `start`, counter-clockwise about `axis` by `sweep` (2 pi for a full circle, where `start` is any point of it).
    case circle(center: Vector3, axis: Vector3, radius: Double, start: Vector3, sweep: Double)
    case point(Vector3)
    /// A cylinder's outline on one side (`side` +1 or -1, the side of `axis x viewDirection`) or its axis (`side` 0).
    case cylinder(axisPoint: Vector3, axis: Vector3, radius: Double, side: Double)
    /// A held edge with no exact curve.
    case other(midpoint: Vector3)
}

/// What an anchor stands for now: its geometry and the edges it was found on, or why it is lost.
public enum AnchorResolution: Hashable, Sendable {
    case held(AnchorGeometry, edges: [EdgeID], isRun: Bool)
    case lost(LostReason)
}
