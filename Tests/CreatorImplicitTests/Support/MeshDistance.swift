import CreatorGeometry
import CreatorImplicit

/// Brute-force distances between meshes, for the tests of the tools that change a surface.
enum MeshDistance {
    /// The point of the triangle (a, b, c) nearest to p (Ericson, Real-Time Collision Detection 5.1.5).
    static func closest(_ p: Vector3, _ a: Vector3, _ b: Vector3, _ c: Vector3) -> Vector3 {
        let (ab, ac, ap) = (b - a, c - a, p - a)
        let (d1, d2) = (ab.dot(ap), ac.dot(ap))
        if d1 <= 0, d2 <= 0 { return a }
        let bp = p - b
        let (d3, d4) = (ab.dot(bp), ac.dot(bp))
        if d3 >= 0, d4 <= d3 { return b }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 { return a + ab * (d1 / (d1 - d3)) }
        let cp = p - c
        let (d5, d6) = (ab.dot(cp), ac.dot(cp))
        if d6 >= 0, d5 <= d6 { return c }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 { return a + ac * (d2 / (d2 - d6)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 { return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))) }
        let denominator = 1 / (va + vb + vc)
        return a + ab * (vb * denominator) + ac * (vc * denominator)
    }

    /// The distance from `p` to the surface of `mesh`.
    static func distance(from p: Vector3, to mesh: TriangleMesh) -> Double {
        var best = Double.infinity
        for index in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.corners(of: index)
            best = min(best, (closest(p, a, b, c) - p).length)
        }
        return best
    }

    /// The largest distance from a vertex or a triangle's centre of `a` to the surface of `b`.
    static func oneWay(from a: TriangleMesh, to b: TriangleMesh) -> Double {
        var worst = 0.0
        for vertex in 0..<a.vertexCount { worst = max(worst, distance(from: a.point(vertex), to: b)) }
        for index in 0..<a.triangleCount {
            let (p, q, r) = a.corners(of: index)
            worst = max(worst, distance(from: (p + q + r) * (1.0 / 3), to: b))
        }
        return worst
    }

    /// The sampled Hausdorff distance: the larger of the two one-way distances.
    static func hausdorff(_ a: TriangleMesh, _ b: TriangleMesh) -> Double {
        max(oneWay(from: a, to: b), oneWay(from: b, to: a))
    }
}
