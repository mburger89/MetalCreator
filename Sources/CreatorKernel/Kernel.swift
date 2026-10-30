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
    func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid
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
    func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid
    func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid
    func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh
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
    /// operation it checks for cancellation on entry. The default refuses.
    func section(_ solid: Solid, by plane: Plane, tolerance: Double) throws -> PlaneSection
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
}
