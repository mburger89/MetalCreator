import CreatorGeometry

/// A geometric constraint (spec §3). Lines are treated as infinite and arcs as full circles
/// wherever a constraint refers to "the line" or "the circle", so trimming a curve never
/// changes what its constraints mean.
public enum SketchConstraint: Hashable, Sendable, Codable {
    /// Two point entities at the same place.
    case coincident(SketchEntityID, SketchEntityID)
    /// A point on a line, arc, circle or projected edge.
    case pointOn(point: SketchEntityID, curve: SketchEntityID)
    /// A line (or projected line) parallel to the x axis.
    case horizontal(SketchEntityID)
    /// A line (or projected line) parallel to the y axis.
    case vertical(SketchEntityID)
    /// Two points at the same y.
    case horizontalPoints(SketchEntityID, SketchEntityID)
    /// Two points at the same x.
    case verticalPoints(SketchEntityID, SketchEntityID)
    case parallel(SketchEntityID, SketchEntityID)
    case perpendicular(SketchEntityID, SketchEntityID)
    /// Line–arc/circle or arc/circle–arc/circle. When the two curves share an endpoint the
    /// tangency is at that point; otherwise it is wherever the curves touch.
    case tangent(SketchEntityID, SketchEntityID)
    /// Equal lengths (two lines) or equal radii (two arcs/circles).
    case equal(SketchEntityID, SketchEntityID)
    /// A point at the midpoint of a line.
    case midpoint(point: SketchEntityID, line: SketchEntityID)
    /// Two arcs/circles sharing a centre.
    case concentric(SketchEntityID, SketchEntityID)
    /// Two points mirrored about a line.
    case symmetric(SketchEntityID, SketchEntityID, about: SketchEntityID)
    /// A point held at `at`.
    case fix(SketchEntityID, at: Vector2)

    /// Every entity this constraint refers to, in declaration order.
    public var entities: [SketchEntityID] {
        switch self {
        case .coincident(let a, let b), .horizontalPoints(let a, let b), .verticalPoints(let a, let b),
             .parallel(let a, let b), .perpendicular(let a, let b), .tangent(let a, let b),
             .equal(let a, let b), .concentric(let a, let b):
            [a, b]
        case .pointOn(let point, let curve): [point, curve]
        case .midpoint(let point, let line): [point, line]
        case .horizontal(let a), .vertical(let a), .fix(let a, _): [a]
        case .symmetric(let a, let b, let line): [a, b, line]
        }
    }
}
