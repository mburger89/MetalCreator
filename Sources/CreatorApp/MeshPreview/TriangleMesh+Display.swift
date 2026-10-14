import CreatorGeometry
import CreatorImplicit
import CreatorKernel

extension TriangleMesh {
    /// The mesh as the viewport draws it (implicit spec §5.1): smooth normals (the mesher's, else the average of the faces at each
    /// vertex), one face for the whole mesh, no B-rep edges. A vertex whose gradient was degenerate when the mesher snapped it keeps a
    /// zero normal there; it is shaded with the faces' average instead of a zero vector (which would draw black).
    var displayMesh: DisplayMesh {
        let points = (0..<vertexCount).map { point($0) }
        var shading = averagedNormals(of: points)
        if normals.count == points.count {
            for (index, normal) in normals.enumerated() where Self.isUsable(normal) {
                shading[index] = Vector3(Double(normal.x), Double(normal.y), Double(normal.z))
            }
        }
        return DisplayMesh(positions: points, normals: shading, indices: triangles,
                           triangleFaces: [FaceID](repeating: FaceID(0), count: triangleCount), edgePolylines: [:])
    }

    /// A normal the mesher set: finite and not the zero it keeps when the gradient was degenerate.
    private static func isUsable(_ normal: SIMD3<Float>) -> Bool {
        normal != .zero && normal.x.isFinite && normal.y.isFinite && normal.z.isFinite
    }

    /// Each vertex's normal as the area-weighted average of the faces around it.
    private func averagedNormals(of points: [Vector3]) -> [Vector3] {
        var sums = [Vector3](repeating: .zero, count: points.count)
        for face in 0..<triangleCount {
            let corners = (0..<3).map { Int(triangles[3 * face + $0]) }
            let normal = (points[corners[1]] - points[corners[0]]).cross(points[corners[2]] - points[corners[0]])
            for corner in corners { sums[corner] += normal }
        }
        return sums.map { $0.normalized ?? .unitZ }
    }
}
