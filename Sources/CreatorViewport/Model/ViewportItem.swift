import CreatorKernel

/// One solid the viewport shows (spec §6.3). The host builds these from the document:
/// - output solids, and last-good results drawn as ghosts while their node is in error (spec §4.4)
/// - the faces and edges the active selection rule picks, which glow pink
/// - guides: the edges a selected rule picks on a solid the scene doesn't show, drawn over the part (`isGuide`)
/// - a field's tint (fields spec §6): a value per mesh vertex and the ramp to draw them in
public struct ViewportItem: Sendable {
    public var solid: Solid
    public var isGhost: Bool
    public var selectedFaces: Set<FaceID>
    public var selectedEdges: Set<EdgeID>
    /// A guide is not part of the scene (spec §6.3, Errata (M6)): it carries a solid the host doesn't show, and only
    /// its `selectedEdges` are drawn, in the selection colour, over the shown scene. They glow where they lie on a
    /// shown part and float free where they don't. A guide's surfaces and edges are otherwise never drawn, picked,
    /// hovered or offered in the face menu, and it never widens `sceneBounds` or the point the camera orbits about.
    public var isGuide: Bool
    /// A number at each vertex of this solid's `DisplayMesh` (`ViewportModel.displayMesh(of:)`, the vertices in its order),
    /// drawn in `fieldRamp`'s colours across the surface. Values that are not one per vertex, or no ramp, draw the plain
    /// surface; a ghost is never tinted.
    public var fieldValues: [Float]?
    public var fieldRamp: FieldRamp?
    /// Faces drawn in the theme's warning colour: the triangles a mesh check flagged (implicit spec §5.1).
    public var warningFaces: Set<FaceID>
    /// Edges drawn in the theme's warning colour in every display mode (a sheet's free edges, NS-5 R14); a selected edge keeps the selection colour.
    public var warningEdges: Set<EdgeID>
    /// A curve (`init(curve:)`): its solid has no faces, only one edge polyline, and the viewport draws every edge in the
    /// reference colour in every display mode. It is never in the ID pass, so it picks nothing and opens no face menu; its
    /// bounds count in `sceneBounds`.
    public var isCurve: Bool

    public init(solid: Solid, isGhost: Bool = false, selectedFaces: Set<FaceID> = [], selectedEdges: Set<EdgeID> = [],
                isGuide: Bool = false, fieldValues: [Float]? = nil, fieldRamp: FieldRamp? = nil, warningFaces: Set<FaceID> = [],
                isCurve: Bool = false, warningEdges: Set<EdgeID> = []) {
        self.solid = solid
        self.isGhost = isGhost
        self.selectedFaces = selectedFaces
        self.selectedEdges = selectedEdges
        self.isGuide = isGuide
        self.fieldValues = fieldValues
        self.fieldRamp = fieldRamp
        self.warningFaces = warningFaces
        self.warningEdges = warningEdges
        self.isCurve = isCurve
    }

    /// A curve on display: a faceless solid around the curve's bounds that shows the curve's polyline as its one edge. The
    /// viewport takes a display-only mesh as it is, so no kernel call is made (the curve's own storage is not used).
    public init(curve: Curve, isGhost: Bool = false) {
        self.init(solid: Self.displaySolid(for: curve), isGhost: isGhost, isCurve: true)
    }

    /// The faceless display solid of `curve`. A viewport tells solids apart by identity, so a host that rebuilds its scene keeps
    /// one per curve and passes it to `init(curveSolid:)`.
    public static func displaySolid(for curve: Curve) -> Solid {
        let mesh = DisplayMesh(positions: [], normals: [], indices: [], triangleFaces: [],
                               edgePolylines: curve.polyline.count >= 2 ? [EdgeID(0): curve.polyline] : [:])
        return Solid(topology: Topology(faces: [], edges: []), bounds: curve.bounds, storage: DisplayMeshStorage(mesh))
    }

    /// A curve on display from a solid `displaySolid(for:)` made.
    public init(curveSolid: Solid, isGhost: Bool = false) {
        self.init(solid: curveSolid, isGhost: isGhost, isCurve: true)
    }
}
