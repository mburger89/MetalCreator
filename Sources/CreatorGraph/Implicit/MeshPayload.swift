import CreatorGeometry

/// What `CreatorGraph` knows of a triangle mesh (implicit spec §2.2): `TriangleMesh` lives in `CreatorImplicit` for the same
/// reason `ImplicitSolid` does (`ImplicitPayload`).
public protocol MeshPayload: Sendable {
    var triangleCount: Int { get }
    /// 16 per vertex and 12 per triangle (implicit spec §2.2).
    var estimatedBytes: Int { get }
    /// What the inspector shows: triangle count, resolution, meshing time and memory (implicit spec §5.2).
    var inspectorFacts: [PayloadFact] { get }
    /// The box around the mesh, or `nil` when it has none or isn't known (a stream's); the inspector joins them for a list of meshes.
    var meshBounds: BoundingBox? { get }
}

extension MeshPayload {
    public var inspectorFacts: [PayloadFact] { [] }
    public var meshBounds: BoundingBox? { nil }
}
