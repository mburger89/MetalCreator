/// Where a preview mesh came from, so the viewport can refine it (implicit spec §4.3): the implicit it meshes and what the refinement
/// works towards. A mesh made at `.export` quality has none.
public struct MeshSource: Sendable {
    public var solid: ImplicitSolid
    public var target: PreviewSchedule.Target

    public init(solid: ImplicitSolid, target: PreviewSchedule.Target) {
        self.solid = solid
        self.target = target
    }
}
