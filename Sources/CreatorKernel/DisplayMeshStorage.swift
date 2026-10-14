import CreatorGeometry

/// The payload of a `Solid` that is only something to look at: a mesh the viewport draws as it draws a tessellated part (implicit
/// spec §5.1). It has no faces or edges to pick and no B-rep behind it, so no kernel operation takes one; the viewport reads the mesh
/// back instead of asking the kernel to tessellate.
public final class DisplayMeshStorage: SolidStorage {
    public let mesh: DisplayMesh

    public init(_ mesh: DisplayMesh) {
        self.mesh = mesh
    }

    public var estimatedBytes: Int { mesh.positions.count * 48 + mesh.indices.count * 4 + mesh.triangleFaces.count * 8 }
}

extension Solid {
    /// A solid that is only `mesh` on display: no topology, bounds around its vertices.
    public convenience init(displaying mesh: DisplayMesh) {
        let bounds = BoundingBox(points: mesh.positions) ?? BoundingBox(min: .zero, max: .zero)
        self.init(topology: Topology(faces: [], edges: []), bounds: bounds, storage: DisplayMeshStorage(mesh))
    }

    /// The mesh this solid is, when it is only a mesh on display.
    public var displayedMesh: DisplayMesh? { (storage as? DisplayMeshStorage)?.mesh }
}
