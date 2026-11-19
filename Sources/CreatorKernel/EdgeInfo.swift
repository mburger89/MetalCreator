import CreatorGeometry

public struct EdgeInfo: Hashable, Sendable {
    public var id: EdgeID
    public var kind: CurveKind
    /// The direction of a straight edge, or the axis of a circular one.
    public var direction: Vector3?
    public var length: Double
    public var midpoint: Vector3
    public var convexity: Convexity
    /// The two adjacent faces. A seam edge lists the same face twice and a boundary edge (a sheet's free edge) lists one.
    public var faces: [FaceID]
    /// The exact line or circle, for projecting the edge into a sketch. `nil` for other curves.
    public var curve: EdgeCurve?
    /// The edge's own names (NURBS spec): set on a sheet's boundary edges, which border one face and so can't be named by
    /// two, and (NS-5, R5) on an edge made by sewing, which holds the union of the tags of the boundary edges sewn into it.
    /// A tagged edge is therefore not necessarily a boundary edge: test `isBoundary`, never `tags.isEmpty`. Empty otherwise.
    public var tags: Set<TopoTag>

    public init(id: EdgeID, kind: CurveKind, direction: Vector3?, length: Double, midpoint: Vector3,
                convexity: Convexity, faces: [FaceID], curve: EdgeCurve? = nil, tags: Set<TopoTag> = []) {
        self.id = id
        self.kind = kind
        self.direction = direction
        self.length = length
        self.midpoint = midpoint
        self.convexity = convexity
        self.faces = faces
        self.curve = curve
        self.tags = tags
    }

    /// A seam (such as the one OCCT puts on every cylindrical wall) borders one face on
    /// both sides. Selection rules exclude seams (spec §5.1).
    public var isSeam: Bool { faces.count == 2 && faces[0] == faces[1] }

    /// A boundary edge borders one face: the free edge of a sheet.
    public var isBoundary: Bool { faces.count == 1 }
}
