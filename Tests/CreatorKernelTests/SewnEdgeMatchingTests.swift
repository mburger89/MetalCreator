import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// NS-5 R5: a sewn edge answers to the key it had as a boundary edge before the sew.
struct SewnEdgeMatchingTests {
    let node = NodeID()

    func tag(_ role: TopoRole) -> TopoTag { TopoTag(node: node, item: 0, role: role) }

    func topology(edgeTags: Set<TopoTag>) -> (Topology, EdgeInfo) {
        let a = FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [tag(.startCap)])
        let b = FaceInfo(id: FaceID(1), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [tag(.endCap)])
        let edge = EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitY, length: 1, midpoint: .zero, convexity: .unknown,
                            faces: [FaceID(0), FaceID(1)], tags: edgeTags)
        return (Topology(faces: [a, b], edges: [edge]), edge)
    }

    @Test func aSewnEdgeMatchesItsPreSewBoundaryKey() throws {
        let t = tag(.boundary(.piece(loop: 0, segment: 2)))
        let (topology, edge) = topology(edgeTags: [t])
        let faceA = topology.faces[0].tags
        let faceB = topology.faces[1].tags
        #expect(topology.edge(edge, matches: EdgeKey(faceA, [t])))
        #expect(topology.edge(edge, matches: EdgeKey(faceB, [t])))
        #expect(!topology.edge(edge, matches: EdgeKey([tag(.unnamed(face: 9))], [t])))
        #expect(topology.key(of: edge) == EdgeKey(faceA, faceB))
    }

    @Test func aTwoFaceEdgeWithoutTagsMatchesAsBefore() {
        let t = tag(.boundary(.piece(loop: 0, segment: 2)))
        let (topology, edge) = topology(edgeTags: [])
        let faceA = topology.faces[0].tags
        let faceB = topology.faces[1].tags
        #expect(topology.edge(edge, matches: EdgeKey(faceA, faceB)))
        #expect(topology.edge(edge, matches: EdgeKey(faceB, faceA)))
        #expect(!topology.edge(edge, matches: EdgeKey(faceA, [t])))
    }
}
