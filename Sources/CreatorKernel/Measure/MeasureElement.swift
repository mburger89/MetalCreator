import CreatorGeometry

/// Something the Measure tool can measure from or to: a face or an edge of a solid, a free point, or a free curve (millimetres).
public enum MeasureElement: Sendable {
    case face(Solid, FaceID)
    case edge(Solid, EdgeID)
    case point(Vector3)
    /// A line or a circle arc, exact (a section's outline).
    case curve(EdgeCurve)
    /// A chain of straight segments through at least two points.
    case polyline([Vector3])
}
