import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorNodes

/// `Topology.pieceCount` (a result of more than one piece is a multi-body compound, spec §11): faces count as joined by an
/// edge between two of them, and by nothing else.
struct PieceCountTests {
    func face(_ id: Int) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [])
    }

    func edge(_ id: Int, faces: [Int]) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: .unitX, length: 1, midpoint: .zero, convexity: .convex,
                 faces: faces.map(FaceID.init))
    }

    @Test func facesJoinedByAnEdgeAreOnePiece() {
        let joined = Topology(faces: [face(0), face(1), face(2)], edges: [edge(0, faces: [0, 1]), edge(1, faces: [1, 2])])
        #expect(joined.pieceCount == 1)
    }

    @Test func anEdgeWithOneFaceJoinsNothing() {
        // Face 2 has an edge of its own that lists a single face: it still stands apart.
        let apart = Topology(faces: [face(0), face(1), face(2)], edges: [edge(0, faces: [0, 1]), edge(1, faces: [2])])
        #expect(apart.pieceCount == 2)
    }

    @Test func aSeamJoinsAFaceToItself() {
        let cylinder = Topology(faces: [face(0), face(1)], edges: [edge(0, faces: [1, 1])])
        #expect(cylinder.pieceCount == 2)
    }
}
