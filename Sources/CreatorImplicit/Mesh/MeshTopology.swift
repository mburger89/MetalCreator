/// What a mesh's connectivity says (implicit spec §2.2, §7): whether it is closed, manifold and consistently oriented, and its Euler
/// characteristic. The tests of every mesher check it on every mesh they make.
public struct MeshTopology: Sendable {
    /// Vertices used by at least one triangle.
    public let usedVertexCount: Int
    public let edgeCount: Int
    public let triangleCount: Int
    /// Edges with a single face.
    public let openEdgeCount: Int
    /// Edges with more than two faces.
    public let overfullEdgeCount: Int
    /// Edges whose two faces run along it the same way (a flipped face).
    public let inconsistentEdgeCount: Int
    /// Triangles with a repeated vertex.
    public let degenerateTriangleCount: Int
    /// Vertices whose faces do not form a single fan.
    public let nonManifoldVertexCount: Int

    public init(_ mesh: TriangleMesh) {
        struct EdgeKey: Hashable {
            var low: UInt32
            var high: UInt32
        }
        // Per edge: how many faces use it, and how many of them run low → high.
        var edges: [EdgeKey: (faces: Int, forward: Int)] = [:]
        var used = Set<UInt32>()
        var degenerate = 0
        var links: [UInt32: [(UInt32, UInt32)]] = [:]
        for index in 0..<mesh.triangleCount {
            let corners = [mesh.triangles[3 * index], mesh.triangles[3 * index + 1], mesh.triangles[3 * index + 2]]
            guard Set(corners).count == 3 else { degenerate += 1; continue }
            for side in 0..<3 {
                let (from, to, other) = (corners[side], corners[(side + 1) % 3], corners[(side + 2) % 3])
                used.insert(from)
                let key = EdgeKey(low: min(from, to), high: max(from, to))
                var entry = edges[key] ?? (0, 0)
                entry.faces += 1
                if from < to { entry.forward += 1 }
                edges[key] = entry
                // The link of `from`: the edge opposite it.
                links[from, default: []].append((to, other))
            }
        }
        usedVertexCount = used.count
        edgeCount = edges.count
        triangleCount = mesh.triangleCount - degenerate
        openEdgeCount = edges.values.filter { $0.faces == 1 }.count
        overfullEdgeCount = edges.values.filter { $0.faces > 2 }.count
        inconsistentEdgeCount = edges.values.filter { $0.faces == 2 && $0.forward != 1 }.count
        degenerateTriangleCount = degenerate
        nonManifoldVertexCount = links.values.filter { !Self.isSingleFan($0) }.count
    }

    /// Whether the link edges of a vertex form one closed cycle.
    private static func isSingleFan(_ link: [(UInt32, UInt32)]) -> Bool {
        var neighbours: [UInt32: [UInt32]] = [:]
        for (a, b) in link {
            neighbours[a, default: []].append(b)
            neighbours[b, default: []].append(a)
        }
        guard neighbours.values.allSatisfy({ $0.count == 2 }), let start = neighbours.keys.first else { return false }
        var seen: Set<UInt32> = [start]
        var stack = [start]
        while let next = stack.popLast() {
            for other in neighbours[next] ?? [] where seen.insert(other).inserted { stack.append(other) }
        }
        return seen.count == neighbours.count
    }

    /// V − E + F over the used vertices: 2 for a sphere, 0 for a torus.
    public var eulerCharacteristic: Int { usedVertexCount - edgeCount + triangleCount }

    /// Every edge has exactly two faces, running opposite ways, no face is degenerate and every vertex has one fan.
    public var isClosedManifold: Bool {
        openEdgeCount == 0 && overfullEdgeCount == 0 && inconsistentEdgeCount == 0 && degenerateTriangleCount == 0
            && nonManifoldVertexCount == 0 && triangleCount > 0
    }
}
