/// What a mesh file reader returns (mesh import spec, Reading).
public struct ImportedMesh: Sendable {
    public var mesh: TriangleMesh
    /// Triangles with a repeated vertex that welding removed.
    public var droppedTriangles: Int
    /// Millimetres per file unit; `nil` for STL, which has none.
    public var unit: Double?
    /// Whether the file held parts the reader does not use (a 3MF's colours, components or extra objects).
    public var ignoredExtras: Bool

    public init(mesh: TriangleMesh, droppedTriangles: Int, unit: Double?, ignoredExtras: Bool) {
        self.mesh = mesh
        self.droppedTriangles = droppedTriangles
        self.unit = unit
        self.ignoredExtras = ignoredExtras
    }
}
