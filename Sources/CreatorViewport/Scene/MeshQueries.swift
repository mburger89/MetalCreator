import CreatorGeometry
import CreatorKernel

/// Questions the viewport asks of a mesh and its topology: where a face is, which way it looks, which edges
/// bound it, and which nodes made it.
enum MeshQueries {
    static func bounds(_ mesh: DisplayMesh) -> BoundingBox? {
        BoundingBox(points: mesh.positions)
    }

    static func faceBounds(_ mesh: DisplayMesh, _ face: FaceID) -> BoundingBox? {
        var points: [Vector3] = []
        forEachTriangle(of: face, in: mesh) { a, b, c in points += [a, b, c] }
        return BoundingBox(points: points)
    }

    static func edgeBounds(_ mesh: DisplayMesh, _ edges: Set<EdgeID>) -> BoundingBox? {
        BoundingBox(points: edges.flatMap { mesh.edgePolylines[$0] ?? [] })
    }

    /// The direction a face looks: its area-weighted triangle normal. That's exact for a plane, and the mean for
    /// a curved face. If the sum cancels out (a full cylinder), it falls back to the first triangle's normal.
    static func faceDirection(_ mesh: DisplayMesh, _ face: FaceID) -> Vector3? {
        var sum = Vector3.zero
        var first: Vector3?
        forEachTriangle(of: face, in: mesh) { a, b, c in
            let normal = (b - a).cross(c - a)
            sum += normal
            if first == nil { first = normal.normalized }
        }
        return sum.normalized ?? first
    }

    /// The edges around a face, seams excluded (spec §5.1), in ID order.
    static func boundaryEdges(of face: FaceID, in topology: Topology) -> [EdgeInfo] {
        topology.edges.filter { !$0.isSeam && $0.faces.contains(face) }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The nodes named in a face's tags (spec §6.3 "Show Producing Node"), unique and sorted.
    static func producingNodes(of face: FaceInfo) -> [NodeID] {
        Set(face.tags.map(\.node)).sorted()
    }

    private static func forEachTriangle(of face: FaceID, in mesh: DisplayMesh,
                                        _ body: (Vector3, Vector3, Vector3) -> Void) {
        let triangles = min(mesh.indices.count / 3, mesh.triangleFaces.count)
        for triangle in 0..<triangles where mesh.triangleFaces[triangle] == face {
            let corners = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            guard corners.allSatisfy({ $0 < mesh.positions.count }) else { continue }
            body(mesh.positions[corners[0]], mesh.positions[corners[1]], mesh.positions[corners[2]])
        }
    }
}
