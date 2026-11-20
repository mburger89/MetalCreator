import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// NS-5: pieces whose keys and centroids tie are ordered by their smallest face.
struct SheetPiecesOrderTests {
    @Test func piecesThatTieAreOrderedByTheirSmallestFace() {
        let node = NodeID()
        // The smaller-index group sits at the larger z (within 1e-9), so only the smallest-face tie-break puts it first.
        let tag = TopoTag(node: node, item: 0, role: .endCap)
        let faces = (0..<4).map {
            FaceInfo(id: FaceID($0), kind: .plane, normal: .unitZ, area: 1, centroid: Vector3(0, 0, $0 < 2 ? 3e-12 : 0), tags: [tag])
        }
        let topology = Topology(faces: faces, edges: [])
        let groups = [[2, 3], [0, 1]]
        let expected = [[FaceID(0), FaceID(1)], [FaceID(2), FaceID(3)]]
        #expect(SheetPieces.ordered(groups: groups, in: topology) == expected)
        #expect(SheetPieces.ordered(groups: groups.reversed(), in: topology) == expected)
    }
}
