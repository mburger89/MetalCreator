/// What a mesh file may be (mesh import spec, Limits). Mesh files are untrusted input: a file is checked against these before it is
/// parsed, so a hostile or mistaken file costs a message, not the machine's memory.
public enum MeshImportLimits {
    /// The most bytes a file may have: 1 GB.
    public static let maxFileBytes = 1 << 30
    /// The most triangles a file may hold.
    public static let maxTriangles = 10_000_000
    /// The most bytes of a mesh file a document embeds: 64 MB.
    public static let maxEmbeddedBytes = 64 * 1024 * 1024
    /// Above this many triangles the node warns that the mesh will be slow.
    public static let warnTriangles = 2_000_000
}
