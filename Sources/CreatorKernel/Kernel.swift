import CreatorGeometry
import Foundation

/// The geometry kernel boundary. Everything above this protocol is pure Swift. OCCT, and
/// any future Swift kernel, live behind it (spec §5.1). Calls are serialized by the actor.
///
/// Conformers must call `try Task.checkCancellation()` on entry to every operation, so calls
/// queued by a superseded evaluation are skipped. `FakeKernel` checks only on entry, never inside an operation; a long
/// `distances` call there is not interrupted part-way (the OCCT kernel checks between its chunks of points).
public protocol Kernel: Actor {
    func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid
    func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid
    /// Lofts through `sections`. A `start` and/or `end` takes that end of the loft from a face of `part` instead of a
    /// profile (the face's outer loop is the first or last section, so `sections` may even be empty for a bridge between
    /// two faces); with `.tangent` or `.curvature` the side surface leaves each edge of that loop G1 or G2 with the part's
    /// face across the edge. The loft's caps keep `.startCap` and `.endCap` and its sides `.side(loop: 0, segment: k)`,
    /// k being the profile segment (a face loop is paired to the sections next to it); none of the part's faces are in the
    /// result, so no tag of the part passes through. A ruled loft takes no face end.
    func loft(_ sections: [Profile2D], ruled: Bool, part: Solid?, start: LoftEnd?, end: LoftEnd?, tag: NodeTag) throws -> Solid
    /// Combines `a` with the tools `b`. The result may be a compound of several disjoint solids
    /// (for example a cut that splits a part in two): multi-body results are deferred (spec §11),
    /// so they pass as one `Solid`. Callers can detect them by topology (faces that form more
    /// than one connected shell); the M3 Boolean node may warn about it.
    func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid
    func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid
    /// Places a copy of each tool, all in one call (patterns spec §3 and §7): copy `i` is `tools[i]` moved by
    /// `transforms[i]`, rotated about its axis first and then translated, as `transform(_:by:tag:)` does. The same
    /// `Solid` may appear in `tools` as often as it likes: it is built once, and its copies differ from it only by
    /// their move (the OCCT kernel copies the geometry per instance; patterns spec §7 sharing is not met). Each copy's
    /// faces carry the tool's tags qualified by its index (`Topology.qualified(item:_:)`): every tag's node becomes
    /// `qualify(node)` and its item `i`, so a pick on one copy names that copy and no other. `tag` names faces the tool's
    /// history doesn't explain. The counts must match; none is an empty result.
    func place(_ tools: [Solid], at transforms: [Transform], qualifying qualify: @Sendable (NodeID) -> NodeID,
               tag: NodeTag) throws -> [Solid]
    /// Rounds `edges` with `radius` in the given cross-section. Faces and tags are the same for every profile.
    func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, profile: FilletProfile, tag: NodeTag) throws -> FilletResult
    func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid
    /// Triangles for display. `angle` is the largest turn in radians between neighbouring normals on a curved face
    /// (`DisplayAngle`); a smaller one makes more triangles. Boxes are the same at any angle.
    func tessellate(_ solid: Solid, tolerance: Double, angle: Double) throws -> DisplayMesh
    func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws
    /// Volume, surface area and centroid. Used by inspectors and the conformance suite.
    func properties(of solid: Solid) throws -> SolidProperties
    /// The distance in millimetres from each of `points` to `target`, in the order of `points` (fields spec §3.1). To a
    /// `.solid` it is to the surface: with `signed`, negative inside and 0 on it; unsigned it is the size of that (so a
    /// point inside is as far from the solid as its nearest wall). `signed` is ignored for `.faces` and `.edges`. Empty
    /// `points` give no distances; an empty or dangling selection is `KernelError.invalidInput` (`DistanceTarget.validate`).
    /// Like every operation it checks for cancellation on entry, and a long batch again between chunks.
    func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double]
    /// A faceted solid made from a closed triangle mesh (Mesh to Solid, implicit spec §4.7): `positions` in millimetres and `triangles`,
    /// three indices per face, counter-clockwise seen from outside. Every face carries the operation tag (`TopoRole.unnamed`), so a
    /// face pick on the result works like on any solid. The mesh must be closed and manifold; a failure names what is wrong with it.
    /// The default refuses: only a kernel with a B-rep can.
    func meshToSolid(positions: [SIMD3<Float>], triangles: [UInt32], tag: NodeTag) throws -> Solid
    /// How `face` of `solid` is parametrized (Face mapping, implicit spec §3.5). The default refuses: only a kernel with surfaces can.
    func faceParametrization(of face: FaceID, in solid: Solid) throws -> FaceParametrization
    /// Where each of `points` stands against `face` of `solid` (Face mapping): the (u, v) of the face's nearest point and the signed
    /// distance along the face's outward normal there, in the order of `points`. A point whose nearest point is on the face's rim has
    /// the rim's (u, v). Like every operation it checks for cancellation on entry, and a long batch again between chunks. An ID the
    /// solid doesn't have is `KernelError.invalidInput`. The default refuses.
    func faceCoordinates(of points: [Vector3], on face: FaceID, in solid: Solid) throws -> [FaceSample]
    /// The cross-section of `solid` by `plane` (section analysis part B): a region per connected piece of material, with triangles to
    /// fill it and its boundary as pieces that keep their exact line or arc and the face they lie on. `tolerance` (millimetres) is the
    /// chord tolerance of the polylines drawn for curved pieces. A plane that misses the solid gives an empty section. Like every
    /// operation it checks for cancellation on entry. The default refuses. `section`, `shortestDistance` and `continuity` are
    /// `async` so that `FakeKernel`'s test hooks can hold a call by suspending: a hook that blocked would hold a thread of Swift's
    /// shared pool, and a few held at once on a small machine starve the pool and hang the test run. Their defaults below stay
    /// synchronous: an `async` default would outrank a kernel's own synchronous method as the witness, silently refusing everything.
    func section(_ solid: Solid, by plane: Plane, tolerance: Double) async throws -> PlaneSection
    /// The exact shortest distance between two picked elements (faces, edges, free points; the solids may differ) and the
    /// nearest point on each, in millimetres. An ID a solid doesn't have is `KernelError.invalidInput`. Like every operation
    /// it checks for cancellation on entry. The default refuses.
    func shortestDistance(between first: MeasureElement, and second: MeasureElement) async throws -> ShapeDistance
    /// How smoothly the two faces meet along `edge` of `solid` (G-b, edge continuity): the worst position, normal-angle and
    /// normal-curvature gaps over 32 samples along the edge, normals oriented outward by the faces' orientation in the solid. A
    /// seam or an edge with fewer than two distinct faces is `KernelError.unsupported`; an ID the solid doesn't have is
    /// `KernelError.invalidInput`. Like every operation it checks for cancellation on entry. The default refuses.
    func continuity(along edge: EdgeID, of solid: Solid) async throws -> EdgeContinuity
    /// How smoothly the free edge `edge` of the sheet `first` meets `face` of `second` (NS-2): the same gaps as `continuity(along:of:)`,
    /// each sample of the edge projected onto the face (samples over 1 mm away or off the trimmed face are skipped), the normals compared up to
    /// sign for the curvature, and the angle gap measured between A's direction continuing past the edge and B's direction leaving it,
    /// so a face folded back over the sheet reads π. An edge that isn't a free edge is
    /// `KernelError.invalidInput` "The edge must be a surface's free edge."; a face the edge doesn't run along (under half the samples usable) "The edge doesn't run along that face.". The default refuses.
    func continuity(of edge: EdgeID, in first: Solid, against face: FaceID, of second: Solid) async throws -> EdgeContinuity
    /// A solid model read from bytes, in millimetres. Every face is tagged `TopoTag(tag, .imported(face: i))`, i its index in the shape's face
    /// map as read; several bodies are one compound. A file with no shapes is refused: "The model contains no shapes.". The default refuses.
    func readModel(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> Solid
    /// `solid` scaled about the origin by `factors` (all finite and greater than 0, else "The scale must be greater than 0."): uniform
    /// is a similarity, uneven OpenCascade's general transform. Face tags are kept face for face. The default refuses.
    func scaled(_ solid: Solid, by factors: Vector3, tag: NodeTag) throws -> Solid
    /// One solid holding all of `solids`, every tag kept. The default refuses.
    func compound(_ solids: [Solid], tag: NodeTag) throws -> Solid
    /// A curve over `pieces`, which must join end to end within 1e-6 mm (else "The curve's pieces don't join end to end."). The default refuses.
    func makeCurve(_ pieces: [CurvePiece], tag: NodeTag) throws -> Curve
    /// A curve through `points` of the given `degree`, periodic when `closed`, with optional end tangents. The default refuses.
    func interpolate(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?, endTangent: Vector3?,
                     tag: NodeTag) throws -> Curve
    /// The curves of `edges` of `solid`, chained end to end. The default refuses.
    func curves(from edges: [EdgeID], of solid: Solid, tag: NodeTag) throws -> [Curve]
    /// The sheet (open surface) swept by `curve` moved along `direction` by `distance`, on both sides of the curve when `symmetric`. The default refuses.
    func extrude(_ curve: Curve, direction: Vector3, distance: Double, symmetric: Bool, tag: NodeTag) throws -> Solid
    /// `curve` turned about `axis` through `angle`. The default refuses.
    func revolve(_ curve: Curve, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid
    /// A surface through `sections`. The default refuses.
    func loftSurface(_ sections: [Curve], ruled: Bool, closed: Bool, tag: NodeTag) throws -> Solid
    /// `profiles` swept along `path`. The default refuses.
    func sweep(_ profiles: [Curve], along path: Curve, options: SweepOptions, tag: NodeTag) throws -> Solid
    /// `profiles` swept along `path`, held to a second rail or a guide surface. The default refuses.
    func sweep(_ profiles: [Curve], along path: Curve, options: SweepOptions, guide: SweepGuide?, tag: NodeTag) throws -> Solid
    /// A planar surface bounded by `loops`. The default refuses.
    func planarSurface(_ loops: [Curve], tag: NodeTag) throws -> Solid
    /// The Gordon surface through a grid of `u` and `v` curves, which may come in any order and direction and must cross
    /// pairwise within `tolerance`. A curve that runs past the border curves is trimmed to them. Asynchronous so a cancelled task stops the build. The default refuses.
    func networkSurface(u: [Curve], v: [Curve], tolerance: Double, tag: NodeTag) async throws -> Solid
    /// One face that fills the closed loop of `boundary` (the pieces of its curves, then its picked edges; 1 to 16 chaining end to end within
    /// 1e-4 mm), through `points` (within 1e-3 mm) and over `interior` curves. A picked sheet edge (one face) is held to `continuity` against that face;
    /// curves and a solid's edges are held in position only. Asynchronous so a cancelled task stops the build. The default refuses.
    func boundaryPatch(_ boundary: PatchBoundary, interior points: [Vector3], interior curves: [Curve],
                       continuity: PatchContinuity, tag: NodeTag) async throws -> PatchResult
    /// `curve` scaled about the origin by `factor`. (A solid or sheet is scaled with `scaled(_:by:tag:)`, which keeps its face and edge tags.) The default refuses.
    func scaled(_ curve: Curve, by factor: Double, tag: NodeTag) throws -> Curve
    /// Every solid, sheet and curve in a model file. The default refuses.
    func readShapes(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> ImportedShapes
    /// Exports `solids` and free `curves`. The default exports solids alone when there are no curves, else refuses.
    func export(_ solids: [Solid], curves: [Curve], format: ExportFormat, to url: URL) throws
    /// The control net of a sheet of one face (NS-3), as one B-spline surface with the normal at each pole's Greville point. A face
    /// that isn't a B-spline is converted exactly. A solid is refused "Edit Surface takes a sheet; this is a closed solid.", a sheet
    /// of other than one face "Edit Surface takes a sheet with one face; this one has N. Rebuild or Split it first.", and a net over
    /// 100,000 poles "This surface has N control points; Edit Surface works on at most 100,000.". The default refuses.
    func controlNet(of surface: Solid) throws -> SurfaceNet
    /// The control net of a curve of one piece (NS-3), a line or arc converted exactly. More pieces are refused "Edit Curve takes a
    /// curve of one piece; this one has N. Rebuild it first.". The default refuses.
    func controlNet(of curve: Curve) throws -> CurveNet
    /// The kind of `face`'s surface and, for a Bezier or B-spline one, its net as it stands. The default refuses.
    func surfaceInfo(of face: FaceID, in solid: Solid) throws -> SurfaceInfo
    /// `surface` (a sheet of one face) with the poles of its control net (`controlNet(of:)`'s) moved by `moves`' offsets, weights
    /// kept (NS-3). The result's faces and edges are the input's, in the same order with the same tags and boundary roles; only
    /// their geometry differs. An index outside the net is refused `.invalidInput`; a move that makes an invalid surface is refused
    /// "Moving these control points makes an invalid surface.". The default refuses.
    func movingPoles(of surface: Solid, by moves: [PoleMove]) throws -> Solid
    /// `curve` (one piece) with its net's poles moved by `moves` (`PoleIndex.j` 0), weights kept; a periodic curve stays periodic
    /// (NS-3). An index outside the net is refused `.invalidInput`. The default refuses.
    func movingPoles(of curve: Curve, by moves: [PoleMove]) throws -> Curve
    /// Whether any face of `sheet` folds over itself (NS-3): neighbouring samples of its surface normal pointing opposite ways, or
    /// a collapsed spot beside an ordinary one. A pole of a degenerate edge (a cone's apex) is not a fold. The default refuses.
    func folds(_ sheet: Solid) throws -> Bool
}

extension Kernel {
    public func meshToSolid(positions: [SIMD3<Float>], triangles: [UInt32], tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("mesh to solid")
    }

    public func faceParametrization(of face: FaceID, in solid: Solid) throws -> FaceParametrization {
        throw KernelError.unsupported("face mapping")
    }

    public func faceCoordinates(of points: [Vector3], on face: FaceID, in solid: Solid) throws -> [FaceSample] {
        throw KernelError.unsupported("face mapping")
    }

    public func section(_ solid: Solid, by plane: Plane, tolerance: Double) throws -> PlaneSection {
        throw KernelError.unsupported("section")
    }

    public func shortestDistance(between first: MeasureElement, and second: MeasureElement) throws -> ShapeDistance {
        throw KernelError.unsupported("measuring")
    }

    public func continuity(along edge: EdgeID, of solid: Solid) throws -> EdgeContinuity {
        throw KernelError.unsupported("continuity")
    }

    public func continuity(of edge: EdgeID, in first: Solid, against face: FaceID, of second: Solid) throws -> EdgeContinuity {
        throw KernelError.unsupported("continuity between bodies")
    }

    public func readModel(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("reading 3D models")
    }

    public func scaled(_ solid: Solid, by factors: Vector3, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("scaling")
    }

    public func compound(_ solids: [Solid], tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("compounds")
    }

    public func makeCurve(_ pieces: [CurvePiece], tag: NodeTag) throws -> Curve {
        throw KernelError.unsupported("curves")
    }

    public func interpolate(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?, endTangent: Vector3?,
                            tag: NodeTag) throws -> Curve {
        throw KernelError.unsupported("interpolated curves")
    }

    public func curves(from edges: [EdgeID], of solid: Solid, tag: NodeTag) throws -> [Curve] {
        throw KernelError.unsupported("curves from edges")
    }

    public func extrude(_ curve: Curve, direction: Vector3, distance: Double, symmetric: Bool, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("extruding a curve")
    }

    public func revolve(_ curve: Curve, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("revolving a curve")
    }

    public func loftSurface(_ sections: [Curve], ruled: Bool, closed: Bool, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("lofting surfaces")
    }

    public func sweep(_ profiles: [Curve], along path: Curve, options: SweepOptions, tag: NodeTag) throws -> Solid {
        try sweep(profiles, along: path, options: options, guide: nil, tag: tag)
    }

    public func sweep(_ profiles: [Curve], along path: Curve, options: SweepOptions, guide: SweepGuide?, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("sweeping")
    }

    public func planarSurface(_ loops: [Curve], tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("planar surfaces")
    }

    public func networkSurface(u: [Curve], v: [Curve], tolerance: Double, tag: NodeTag) async throws -> Solid {
        throw KernelError.unsupported("network surfaces")
    }

    public func boundaryPatch(_ boundary: PatchBoundary, interior points: [Vector3], interior curves: [Curve],
                              continuity: PatchContinuity, tag: NodeTag) async throws -> PatchResult {
        throw KernelError.unsupported("boundary patches")
    }

    public func scaled(_ curve: Curve, by factor: Double, tag: NodeTag) throws -> Curve {
        throw KernelError.unsupported("scaling")
    }

    public func controlNet(of surface: Solid) throws -> SurfaceNet {
        throw KernelError.unsupported("control nets")
    }

    public func controlNet(of curve: Curve) throws -> CurveNet {
        throw KernelError.unsupported("control nets")
    }

    public func surfaceInfo(of face: FaceID, in solid: Solid) throws -> SurfaceInfo {
        throw KernelError.unsupported("surface information")
    }

    public func movingPoles(of surface: Solid, by moves: [PoleMove]) throws -> Solid {
        throw KernelError.unsupported("moving control points")
    }

    public func movingPoles(of curve: Curve, by moves: [PoleMove]) throws -> Curve {
        throw KernelError.unsupported("moving control points")
    }

    public func folds(_ sheet: Solid) throws -> Bool {
        throw KernelError.unsupported("fold detection")
    }

    public func readShapes(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> ImportedShapes {
        throw KernelError.unsupported("reading 3D models")
    }

    public func export(_ solids: [Solid], curves: [Curve], format: ExportFormat, to url: URL) throws {
        guard curves.isEmpty else { throw KernelError.unsupported("exporting curves") }
        try export(solids, format: format, to: url)
    }
}

/// Angular deflections for display meshes, in radians.
public enum DisplayAngle {
    /// The everyday display mesh.
    public static let standard = 0.5
    /// Fine enough that zebra stripes, which reflect the normal, don't show the tessellation.
    public static let zebra = 0.05
}

extension Kernel {
    /// A circular fillet.
    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try fillet(solid, edges: edges, radius: radius, profile: .circular, tag: tag).solid
    }
}

extension Kernel {
    /// Tessellates at `DisplayAngle.standard`.
    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try tessellate(solid, tolerance: tolerance, angle: DisplayAngle.standard)
    }
}

public extension Kernel {
    /// A loft through profiles alone.
    func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try loft(sections, ruled: ruled, part: nil, start: nil, end: nil, tag: tag)
    }
}
