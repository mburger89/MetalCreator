import CreatorGeometry

/// Something the Measure tool can measure from or to: a face or an edge of a solid, or a free point (millimetres).
public enum MeasureElement: Sendable {
    case face(Solid, FaceID)
    case edge(Solid, EdgeID)
    case point(Vector3)
}
