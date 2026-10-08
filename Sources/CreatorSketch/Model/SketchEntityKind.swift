import CreatorGeometry

/// The geometry of a sketch entity (spec §3). Lines and arcs reference shared point entities,
/// so coincidence at a shared endpoint is structural.
public enum SketchEntityKind: Hashable, Sendable, Codable {
    /// A point; the vector is its drawn position. Unknowns: x, y.
    case point(Vector2)
    /// A line between two point entities. No unknowns of its own.
    case line(start: SketchEntityID, end: SketchEntityID)
    /// A counter-clockwise arc around `center` from `start` to `end`, all point entities.
    /// The solver adds the implicit constraint |end − center| = |start − center|.
    case arc(center: SketchEntityID, start: SketchEntityID, end: SketchEntityID)
    /// A full circle around a point entity. Unknown: the radius (this value is the drawn radius).
    case circle(center: SketchEntityID, radius: Double)
    /// A model edge projected onto the sketch plane. Fixed: it has no unknowns.
    case projected(ProjectionSource)
}
