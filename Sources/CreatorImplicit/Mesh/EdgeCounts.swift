/// How a mesh's edges pair up, counted by sorting rather than by a dictionary so a mesh of millions of triangles costs one array
/// (mesh import spec, Reading). The same three numbers as `MeshTopology`, which stays the reference for the tests.
public struct EdgeCounts: Sendable {
    /// Edges with a single face.
    public let open: Int
    /// Edges with more than two faces.
    public let overfull: Int
    /// Edges whose two faces run along it the same way.
    public let flipped: Int

    /// Closed, manifold along its edges and consistently oriented.
    public var isClosed: Bool { open == 0 && overfull == 0 && flipped == 0 }

    public init(_ mesh: TriangleMesh) {
        // Each edge is its lower vertex, its higher vertex and one bit for the direction it is walked; indices are below 2^31
        // (a mesh holds at most 30 million vertices), so the three fit a UInt64 and one sort groups an edge's faces.
        var keys: [UInt64] = []
        keys.reserveCapacity(mesh.triangles.count)
        for base in stride(from: 0, to: mesh.triangles.count - 2, by: 3) {
            for side in 0..<3 {
                let from = mesh.triangles[base + side]
                let to = mesh.triangles[base + (side + 1) % 3]
                guard from != to else { continue }
                let (low, high) = (min(from, to), max(from, to))
                keys.append(UInt64(low) << 32 | UInt64(high) << 1 | (from < to ? 1 : 0))
            }
        }
        keys.sort()
        var open = 0, overfull = 0, flipped = 0
        var start = 0
        while start < keys.count {
            var end = start + 1
            var forward = Int(keys[start] & 1)
            while end < keys.count, keys[end] >> 1 == keys[start] >> 1 {
                forward += Int(keys[end] & 1)
                end += 1
            }
            let faces = end - start
            if faces == 1 {
                open += 1
            } else if faces > 2 {
                overfull += 1
            } else if forward != 1 {
                flipped += 1
            }
            start = end
        }
        (self.open, self.overfull, self.flipped) = (open, overfull, flipped)
    }
}
