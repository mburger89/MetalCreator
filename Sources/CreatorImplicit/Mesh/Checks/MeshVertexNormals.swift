/// Unit normals at the vertices of a mesh for the checks: the mesher's own (from the gradient of the implicit) where it set one, else the
/// average of the faces around the vertex weighted by area.
enum MeshVertexNormals {
    static func of(_ mesh: TriangleMesh) -> [SIMD3<Double>] {
        var sums = [SIMD3<Double>](repeating: .zero, count: mesh.vertexCount)
        let points = mesh.positions.map { SIMD3<Double>($0) }
        for base in stride(from: 0, to: mesh.triangles.count - 2, by: 3) {
            let corners = (0..<3).map { Int(mesh.triangles[base + $0]) }
            let normal = (points[corners[1]] - points[corners[0]]).cross(points[corners[2]] - points[corners[0]])
            for corner in corners { sums[corner] += normal }
        }
        let own = mesh.normals.count == mesh.vertexCount
        return (0..<mesh.vertexCount).map { index in
            if own {
                let given = SIMD3<Double>(mesh.normals[index])
                let length = given.length
                if length > 0.5, length.isFinite { return given / length }
            }
            let length = sums[index].length
            return length > 0 ? sums[index] / length : .zero
        }
    }
}
