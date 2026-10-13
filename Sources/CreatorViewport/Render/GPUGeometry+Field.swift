import CreatorKernel

extension GPUGeometry {
    /// One field value per de-indexed corner, in the order `meshVertices` makes the corners (the same triangles are skipped), so
    /// the tint's vertex shader reads `values[vertex_id]`. A value that is not a number becomes the ramp's middle. `nil` when
    /// `values` is not one per vertex of the mesh.
    static func fieldCorners(_ mesh: DisplayMesh, values: [Float], ramp: FieldRamp) -> [Float]? {
        guard values.count == mesh.positions.count else { return nil }
        let triangles = min(mesh.indices.count / 3, mesh.triangleFaces.count)
        var corners: [Float] = []
        corners.reserveCapacity(triangles * 3)
        for triangle in 0..<triangles {
            let vertices = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            guard vertices.allSatisfy({ $0 < mesh.positions.count && $0 < mesh.normals.count }) else { continue }
            for vertex in vertices {
                let value = values[vertex]
                corners.append(value.isFinite ? value : ramp.midValue)
            }
        }
        return corners
    }
}
