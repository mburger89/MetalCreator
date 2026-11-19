import CreatorGeometry

/// How Trim Surface and Split Surface project open or closed curves onto a sheet (NS-4, R7).
public enum TrimProjection: Int, Sendable { case alongDirection = 0, alongNormals = 1 }

/// What divides a sheet: curves projected onto it, or the faces of a body (a sheet or a solid).
public enum TrimCutter: Sendable {
    case curves([Curve], projection: TrimProjection, direction: Vector3)
    case body(Solid)
}

/// A sheet divided by a cutter: the whole split as one sheet, the connected pieces as lists of its faces, and, for a closed cutter,
/// the faces inside it (`nil` when the cutter isn't closed, R4).
public struct SheetSplit: Sendable {
    public var whole: Solid
    public var pieces: [[FaceID]]
    public var inside: Set<FaceID>?
    public var warnings: [String]

    public init(whole: Solid, pieces: [[FaceID]], inside: Set<FaceID>?, warnings: [String] = []) {
        self.whole = whole
        self.pieces = pieces
        self.inside = inside
        self.warnings = warnings
    }
}

/// How Extend Surface grows a sheet (NS-4, R8): along the surface's own continuation, or straight along the cross tangent.
public enum ExtendMode: Int, Sendable { case natural = 0, linear = 1 }

/// One side of a Blend Surface (NS-4, R10): an edge of a sheet or solid, how the blend meets it and how far its tangent reaches.
public struct SurfaceBlendEnd: Sendable {
    public var body: Solid
    public var edge: EdgeID
    public var continuity: PatchContinuity
    public var bulge: Double

    public init(body: Solid, edge: EdgeID, continuity: PatchContinuity, bulge: Double) {
        self.body = body
        self.edge = edge
        self.continuity = continuity
        self.bulge = bulge
    }
}
