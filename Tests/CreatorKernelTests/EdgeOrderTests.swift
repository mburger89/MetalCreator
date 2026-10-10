import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// `Topology.edges(matching:)` orders the edges of one key by midpoint, then by ID (spec §5.3, rule 5). Ordinals saved in a
/// pick index that order, so what counts as a tie is part of the file format.
struct EdgeOrderTests {
    let node = NodeID()
    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 0)) }

    func edge(_ id: Int, at midpoint: Vector3) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: .unitX, length: 1, midpoint: midpoint, convexity: .convex,
                 faces: [FaceID(0), FaceID(1)])
    }

    func order(_ edges: [EdgeInfo]) -> [Int] {
        let topology = Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [side]),
        ], edges: edges)
        return topology.edges(matching: EdgeKey([top], [side])).map(\.id.rawValue)
    }

    @Test func midpointsThatDifferByMoreThanAMicrometreOrderByPosition() {
        // The lower ID is the farther along x.
        #expect(order([edge(1, at: Vector3(5, 0, 0)), edge(2, at: Vector3(-5, 0, 0))]) == [2, 1])
        #expect(order([edge(1, at: Vector3(2e-6, 0, 0)), edge(2, at: .zero)]) == [2, 1], "2 µm apart is a real difference")
    }

    @Test func midpointsWithinAMicrometreTieAndOrderByID() {
        // x, y and z each within 1e-6 mm of each other, so the IDs decide, whichever order the topology lists them in.
        let near = [edge(7, at: .zero), edge(3, at: Vector3(5e-7, 0, 0)), edge(5, at: Vector3(0, 0, -5e-7))]
        #expect(order(near) == [3, 5, 7])
        #expect(order(near.reversed()) == [3, 5, 7])
    }
}
