import CreatorGeometry

/// A curve a tool is about to draw, in plane coordinates (the rubber band).
public enum PreviewCurve: Hashable, Sendable {
    case line(Vector2, Vector2)
    case circle(center: Vector2, radius: Double)
    /// Counter-clockwise from `start` around `center` to the ray through `end`, as `Sketch.addArc` draws it.
    case arc(center: Vector2, start: Vector2, end: Vector2)
    /// A spline through these fit points, with automatic handles.
    case spline(through: [Vector2])
}
