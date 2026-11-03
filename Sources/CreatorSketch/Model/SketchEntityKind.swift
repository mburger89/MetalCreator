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
    /// A degree-5 spline through two or more fit points, all point entities in order (`SplineDefinition`). `handles` has one
    /// entry per fit point: which of its two handles are active (the solver's, with values in `Sketch.solved`) and which are
    /// automatic. The curve is a pure function of the fit points and the active handles.
    case spline(points: [SketchEntityID], handles: [SplineHandleState])
}

/// Which of a fit point's two handles are active. An inactive (automatic) handle has no unknowns: the spline fills it in.
public struct SplineHandleState: Hashable, Sendable, Codable {
    public var tangent: Bool
    public var curvature: Bool

    public init(tangent: Bool = false, curvature: Bool = false) {
        self.tangent = tangent
        self.curvature = curvature
    }

    public static let automatic = SplineHandleState()
}
