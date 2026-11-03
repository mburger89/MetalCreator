/// What a mesh file reader returns (mesh import spec, Reading).
public struct ImportedMesh: Sendable {
    public var mesh: TriangleMesh
    /// Triangles with a repeated vertex that welding removed.
    public var droppedTriangles: Int
    /// Millimetres per file unit; `nil` for STL, which has none.
    public var unit: Double?
    /// Whether the file held data the reader does not use and says so: a 3MF's colours, materials, textures, slices and beam lattices.
    public var ignoredExtras: Bool
    /// Whether a 3MF's support structures (objects of type support, solidsupport or other) were left out.
    public var supportsLeftOut: Bool

    public init(mesh: TriangleMesh, droppedTriangles: Int, unit: Double?, ignoredExtras: Bool, supportsLeftOut: Bool = false) {
        self.supportsLeftOut = supportsLeftOut
        self.mesh = mesh
        self.droppedTriangles = droppedTriangles
        self.unit = unit
        self.ignoredExtras = ignoredExtras
    }
}
