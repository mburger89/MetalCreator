// Test fixture file: a big flat mesh for the renderer tests.
import CreatorGeometry
import CreatorKernel

extension TestMeshes {
    /// A sheet of `columns` × `rows` quads (two triangles each, 2 × `columns` × `rows` triangles) facing the front (−Y), filling
    /// `bounds`' x and z at `bounds.min.y`. One face (0), no edges.
    static func sheet(_ bounds: BoundingBox, columns: Int, rows: Int) -> DisplayMesh {
        var positions: [Vector3] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            for column in 0...columns {
                positions.append(Vector3(bounds.min.x + (bounds.max.x - bounds.min.x) * Double(column) / Double(columns), bounds.min.y,
                                         bounds.min.z + (bounds.max.z - bounds.min.z) * Double(row) / Double(rows)))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(columns * rows * 6)
        for row in 0..<rows {
            for column in 0..<columns {
                let corner = UInt32(row * (columns + 1) + column)
                let across = UInt32(columns + 1)
                indices += [corner, corner + 1, corner + across + 1, corner, corner + across + 1, corner + across]
            }
        }
        return DisplayMesh(positions: positions, normals: Array(repeating: Vector3(0, -1, 0), count: positions.count), indices: indices,
                           triangleFaces: Array(repeating: FaceID(0), count: indices.count / 3), edgePolylines: [:])
    }
}
