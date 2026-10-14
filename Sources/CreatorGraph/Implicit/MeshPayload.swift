/// What `CreatorGraph` knows of a triangle mesh (implicit spec §2.2): `TriangleMesh` lives in `CreatorImplicit` for the same
/// reason `ImplicitSolid` does (`ImplicitPayload`).
public protocol MeshPayload: Sendable {
    var triangleCount: Int { get }
    /// 16 per vertex and 12 per triangle (implicit spec §2.2).
    var estimatedBytes: Int { get }
}
