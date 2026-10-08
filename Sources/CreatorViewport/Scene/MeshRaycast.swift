import CreatorGeometry
import CreatorKernel

/// CPU ray casting against display meshes, for the orbit pivot (spec §6.3: "orbit pivots on the point under the
/// cursor"). The ID pass gives identities, not depths.
enum MeshRaycast {
    static func nearest(_ ray: Ray, in meshes: [(solidIndex: Int, mesh: DisplayMesh)]) -> RayHit? {
        var best: RayHit?
        for (solidIndex, mesh) in meshes {
            let triangles = min(mesh.indices.count / 3, mesh.triangleFaces.count)
            for triangle in 0..<triangles {
                let a = Int(mesh.indices[3 * triangle])
                let b = Int(mesh.indices[3 * triangle + 1])
                let c = Int(mesh.indices[3 * triangle + 2])
                guard a < mesh.positions.count, b < mesh.positions.count, c < mesh.positions.count,
                      let t = intersect(ray, mesh.positions[a], mesh.positions[b], mesh.positions[c]),
                      t >= ray.minimumT, t < (best?.distance ?? .infinity) else { continue }
                best = RayHit(point: ray.point(at: t), distance: t, solidIndex: solidIndex, face: mesh.triangleFaces[triangle])
            }
        }
        return best
    }

    /// Möller–Trumbore, two-sided: the ray parameter where `ray`'s line crosses triangle abc, or `nil`.
    static func intersect(_ ray: Ray, _ a: Vector3, _ b: Vector3, _ c: Vector3) -> Double? {
        let e1 = b - a
        let e2 = c - a
        let p = ray.direction.cross(e2)
        let determinant = e1.dot(p)
        guard abs(determinant) > 1e-12 else { return nil }
        let inverse = 1 / determinant
        let s = ray.origin - a
        let u = s.dot(p) * inverse
        guard u >= 0, u <= 1 else { return nil }
        let q = s.cross(e1)
        let v = ray.direction.dot(q) * inverse
        guard v >= 0, u + v <= 1 else { return nil }
        return e2.dot(q) * inverse
    }
}
