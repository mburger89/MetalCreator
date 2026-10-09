import CreatorGeometry

public struct EdgeInfo: Hashable, Sendable {
    public var id: EdgeID
    public var kind: CurveKind
    /// The direction of a straight edge, or the axis of a circular one.
    public var direction: Vector3?
    public var length: Double
    public var midpoint: Vector3
    public var convexity: Convexity
    /// The two adjacent faces. A seam edge lists the same face twice.
    public var faces: [FaceID]
    /// The exact line or circle, for projecting the edge into a sketch. `nil` for other curves.
    public var curve: EdgeCurve?

    public init(id: EdgeID, kind: CurveKind, direction: Vector3?, length: Double, midpoint: Vector3,
                convexity: Convexity, faces: [FaceID], curve: EdgeCurve? = nil) {
        self.id = id
        self.kind = kind
        self.direction = direction
        self.length = length
        self.midpoint = midpoint
        self.convexity = convexity
        self.faces = faces
        self.curve = curve
    }

    /// A seam (such as the one OCCT puts on every cylindrical wall) borders one face on
    /// both sides. Selection rules exclude seams (spec §5.1).
    public var isSeam: Bool { faces.count == 2 && faces[0] == faces[1] }
}
