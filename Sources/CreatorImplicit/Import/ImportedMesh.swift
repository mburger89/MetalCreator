/// What a mesh file reader returns (mesh import spec, Reading).
public struct ImportedMesh: Sendable {
    public var mesh: TriangleMesh
    /// Triangles with a repeated vertex that welding removed.
    public var droppedTriangles: Int
    /// Millimetres per file unit; `nil` for STL, which has none.
    public var unit: Double?
    /// Whether the file held data the reader does not use and says so: a 3MF's colours, materials, textures, slices and beam lattices.
    public var ignoredExtras: Bool
    /// Whether a 3MF's support, modifier or negative parts (objects of type support, solidsupport or other) were left out.
    public var partsLeftOut: Bool
    /// How the mesh's edges pair up, counted once when the file is parsed and kept with it, so a placement or units edit does not
    /// sort the edges again (0.5 s at 10 million triangles). `nil` until someone counts; `Import Mesh` falls back to counting.
    public var edgeCounts: EdgeCounts?

    public init(mesh: TriangleMesh, droppedTriangles: Int, unit: Double?, ignoredExtras: Bool, partsLeftOut: Bool = false) {
        self.partsLeftOut = partsLeftOut
        self.mesh = mesh
        self.droppedTriangles = droppedTriangles
        self.unit = unit
        self.ignoredExtras = ignoredExtras
    }
}
