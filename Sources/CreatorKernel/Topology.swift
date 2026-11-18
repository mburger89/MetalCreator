/// The Swift-side description of a solid's faces and edges, used by selection rules.
public struct Topology: Hashable, Sendable {
    public var faces: [FaceInfo]
    public var edges: [EdgeInfo]

    public init(faces: [FaceInfo], edges: [EdgeInfo]) {
        self.faces = faces
        self.edges = edges
    }

    public func face(_ id: FaceID) -> FaceInfo? { faces.first { $0.id == id } }
    public func edge(_ id: EdgeID) -> EdgeInfo? { edges.first { $0.id == id } }

    /// The edge's stable name, or `nil` if an adjacent face is missing from the table or a boundary edge has no tags.
    public func key(of edge: EdgeInfo) -> EdgeKey? {
        if edge.faces.count == 1 {
            // A boundary edge is named by its face and its own tags; one without tags is never picked.
            guard !edge.tags.isEmpty, let face = face(edge.faces[0]) else { return nil }
            return EdgeKey(face.tags, edge.tags)
        }
        guard edge.faces.count == 2, let a = face(edge.faces[0]), let b = face(edge.faces[1]) else { return nil }
        return EdgeKey(a.tags, b.tags)
    }
}
