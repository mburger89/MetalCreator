import CreatorGeometry

/// Triangles for display and picking, plus the B-rep edges as polylines.
public struct DisplayMesh: Sendable {
    public var positions: [Vector3]
    public var normals: [Vector3]
    public var indices: [UInt32]
    /// The face each triangle belongs to (`indices.count / 3` entries).
    public var triangleFaces: [FaceID]
    public var edgePolylines: [EdgeID: [Vector3]]

    public init(positions: [Vector3], normals: [Vector3], indices: [UInt32], triangleFaces: [FaceID], edgePolylines: [EdgeID: [Vector3]]) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.triangleFaces = triangleFaces
        self.edgePolylines = edgePolylines
    }
}
