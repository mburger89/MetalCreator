import CreatorGeometry
import CreatorImplicit
import Foundation

extension TriangleMesh {
    /// The display of a mesh with a `creaseAngle` and no normals of its own (mesh import spec, "The display: hard edges"). Triangle
    /// `t` keeps its place; only the vertices it points at change. A crease is an edge whose two faces turn more than the angle
    /// (exactly the angle is smooth), or an edge that isn't shared by exactly two faces wound against each other (open, over-full or
    /// flipped). A vertex's faces are joined across the edges that are not creases, and each joined group gets one display vertex
    /// with the area-weighted average of its faces' normals. The first group of each vertex keeps the vertex's own index, so a vertex
    /// that never splits is where it was and the extra copies follow the originals. The work is linear in the triangles: the half-edges
    /// are bucketed by origin vertex (a counting sort), each edge looks for its twin among its end vertices' few half-edges, and the
    /// groups are a union-find over the corners.
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
    private func joinSmoothCorners(_ parent: inout [Int32], faceNormals: [SIMD3<Float>], cosine: Double) {
        let cornerCount = triangles.count
        // The half-edges leaving each vertex: a half-edge is the corner it starts at.
        var start = [Int32](repeating: 0, count: vertexCount + 1)
        for vertex in triangles { start[Int(vertex) + 1] += 1 }
        for index in 0..<vertexCount { start[index + 1] += start[index] }
        var fill = start
        var leaving = [Int32](repeating: 0, count: cornerCount)
        for corner in 0..<cornerCount {
            let vertex = Int(triangles[corner])
            leaving[Int(fill[vertex])] = Int32(corner)
            fill[vertex] += 1
        }
        let limit = Float(cosine - 1e-6)
        for corner in 0..<cornerCount {
            guard let twin = smoothTwin(of: corner, start: start, leaving: leaving, faceNormals: faceNormals, limit: limit) else {
                continue
            }
            Self.union(&parent, Int32(corner), Int32(Self.nextCorner(twin)))
            Self.union(&parent, Int32(Self.nextCorner(corner)), Int32(twin))
        }
    }

    /// The half-edge that runs the other way along `corner`'s edge when the edge is shared by exactly those two faces and turns no more
    /// than the angle (`limit` is its cosine). `nil` for a crease, and for the twin's own visit (each edge is joined once, from its
    /// lower half-edge).
    private func smoothTwin(of corner: Int, start: [Int32], leaving: [Int32], faceNormals: [SIMD3<Float>], limit: Float) -> Int? {
        let from = Int(triangles[corner]), to = Int(triangles[Self.nextCorner(corner)])
        guard from != to else { return nil }
        // Exactly one half-edge runs the other way and none the same way: two faces wound against each other.
        var twin = -1, twins = 0
        for slot in Int(start[to])..<Int(start[to + 1]) {
            let other = Int(leaving[slot])
            if Int(triangles[Self.nextCorner(other)]) == from { twins += 1; twin = other }
        }
        guard twins == 1, twin > corner else { return nil }
        for slot in Int(start[from])..<Int(start[from + 1]) {
            let other = Int(leaving[slot])
            if other != corner, Int(triangles[Self.nextCorner(other)]) == to { return nil }
        }
        let here = faceNormals[corner / 3], there = faceNormals[twin / 3]
        return here == .zero || there == .zero || (here * there).sum() >= limit ? twin : nil
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
