import CreatorGeometry
import Foundation

/// The geometry kernel boundary. Everything above this protocol is pure Swift. OCCT, and
/// any future Swift kernel, live behind it (spec §5.1). Calls are serialized by the actor.
///
/// Conformers must call `try Task.checkCancellation()` on entry to every operation, so calls
/// queued by a superseded evaluation are skipped.
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
}
