/// Where a preview mesh came from, so the viewport can refine it (implicit spec §4.3): the implicit it meshes and the resolution the
/// refinement works towards. A mesh made at `.export` quality has none.
public struct MeshSource: Sendable {
    public var solid: ImplicitSolid
    /// The voxel size the last refinement pass meshes at, in millimetres.
    public var targetResolution: Double

    public init(solid: ImplicitSolid, targetResolution: Double) {
        self.solid = solid
        self.targetResolution = targetResolution
    }
}
