import CreatorGeometry
import CreatorImplicit
import Foundation

extension TriangleMesh {
    /// The display of a mesh with a `creaseAngle` and no normals of its own (mesh import spec, "The display: hard edges"). Triangle
    /// `t` keeps its place; only the vertices it points at change. A crease is an edge whose two faces turn more than the angle
    /// (exactly the angle is smooth), or an edge that isn't shared by exactly two faces wound against each other (open, over-full or
    /// flipped). A vertex's faces are joined across the edges that are not creases, and each joined group gets one display vertex
    /// with the area-weighted average of its faces' normals. The first group of each vertex keeps the vertex's own index, so a vertex
    /// that never splits is where it was and the extra copies follow the originals. The work is O(n log n) in the triangles: the half-edges
    /// are matched by sorting their edge keys (`joinSmoothCorners`), so a hub vertex costs no more than any other, and the groups are a
    /// union-find over the corners.
    func creasedDisplay(angle: Double) -> (positions: [Vector3], normals: [Vector3], indices: [UInt32]) {
        let cornerCount = triangles.count
        let faceNormals = unitFaceNormals()
        var parent = (0..<cornerCount).map { Int32($0) }
        joinSmoothCorners(&parent, faceNormals: faceNormals, cosine: cos(angle * .pi / 180))

        var points = (0..<vertexCount).map { point($0) }
        var taken = [Bool](repeating: false, count: vertexCount)
        var slot = [Int32](repeating: -1, count: cornerCount)
        var indices = [UInt32](repeating: 0, count: cornerCount)
        for corner in 0..<cornerCount {
            let root = Self.find(&parent, Int32(corner))
            if slot[Int(root)] < 0 {
                let vertex = Int(triangles[corner])
                if taken[vertex] {
                    slot[Int(root)] = Int32(points.count)
                    points.append(point(vertex))
                } else {
                    slot[Int(root)] = Int32(vertex)
                    taken[vertex] = true
                }
            }
            indices[corner] = UInt32(slot[Int(root)])
        }

        var sums = [Vector3](repeating: .zero, count: points.count)
        for triangle in 0..<triangleCount {
            let (a, b, c) = corners(of: triangle)
            let weighted = (b - a).cross(c - a)
            for corner in 0..<3 { sums[Int(indices[3 * triangle + corner])] += weighted }
        }
        return (points, sums.map { $0.normalized ?? .unitZ }, indices)
    }

    /// The unit normal of each triangle, or zero for a degenerate one (which joins every neighbour instead of splitting it).
    private func unitFaceNormals() -> [SIMD3<Float>] {
        (0..<triangleCount).map { triangle in
            let (a, b, c) = corners(of: triangle)
            guard let unit = (b - a).cross(c - a).normalized else { return .zero }
            return SIMD3<Float>(Float(unit.x), Float(unit.y), Float(unit.z))
        }
    }

    /// Unites the corners (a triangle's vertex slot, `3 * triangle + k`) that meet at a vertex across an edge that isn't a crease.
    /// Half-edges are matched by sorting their edge keys, so the cost is O(n log n) whatever the valence of a vertex (a hub with
    /// 100,000 triangles is no worse than any other).
    private func joinSmoothCorners(_ parent: inout [Int32], faceNormals: [SIMD3<Float>], cosine: Double) {
        let cornerCount = triangles.count
        var edges: [EdgeEntry] = []
        edges.reserveCapacity(cornerCount)
        for corner in 0..<cornerCount {
            let from = triangles[corner], to = triangles[Self.nextCorner(corner)]
            guard from != to else { continue }
            edges.append(EdgeEntry(key: UInt64(min(from, to)) << 32 | UInt64(max(from, to)), corner: Int32(corner)))
        }
        edges.sort { $0.key != $1.key ? $0.key < $1.key : $0.corner < $1.corner }
        let limit = Float(cosine - 1e-6)
        var index = 0
        while index < edges.count {
            var end = index + 1
            while end < edges.count, edges[end].key == edges[index].key { end += 1 }
            defer { index = end }
            // Exactly two half-edges, running opposite ways: two faces wound against each other. Anything else is a crease.
            guard end - index == 2 else { continue }
            let first = Int(edges[index].corner), second = Int(edges[index + 1].corner)
            guard triangles[first] != triangles[second] else { continue }
            let here = faceNormals[first / 3], there = faceNormals[second / 3]
            guard here == .zero || there == .zero || (here * there).sum() >= limit else { continue }
            Self.union(&parent, Int32(first), Int32(Self.nextCorner(second)))
            Self.union(&parent, Int32(Self.nextCorner(first)), Int32(second))
        }
    }

    /// A half-edge and the unordered pair of vertices it joins.
    private struct EdgeEntry {
        var key: UInt64
        var corner: Int32
    }

    /// The corner after `corner` in its triangle.
    private static func nextCorner(_ corner: Int) -> Int { corner % 3 == 2 ? corner - 2 : corner + 1 }

    private static func find(_ parent: inout [Int32], _ corner: Int32) -> Int32 {
        var root = corner
        while parent[Int(root)] != root { root = parent[Int(root)] }
        var walker = corner
        while parent[Int(walker)] != root {
            let up = parent[Int(walker)]
            parent[Int(walker)] = root
            walker = up
        }
        return root
    }

    private static func union(_ parent: inout [Int32], _ first: Int32, _ second: Int32) {
        let a = find(&parent, first), b = find(&parent, second)
        if a != b { parent[Int(max(a, b))] = min(a, b) }
    }
}
