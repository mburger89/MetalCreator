import CreatorImplicit

/// What a mesh socket holds for a node that works on meshes: the mesh itself, or, while an export streams, the stream that will make it.
enum MeshValue {
    case mesh(TriangleMesh)
    case stream(MeshStream)
}
