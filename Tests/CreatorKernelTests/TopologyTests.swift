import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct TopologyTests {
    let node = NodeID()

    @Test func edgeKeyIsUnordered() {
        let top: Set = [TopoTag(node: node, item: 0, role: .endCap)]
        let side: Set = [TopoTag(node: node, item: 0, role: .side(segment: 2))]
        #expect(EdgeKey(top, side) == EdgeKey(side, top))
        #expect(EdgeKey(top, side).hashValue == EdgeKey(side, top).hashValue)
    }

    @Test func broadcastItemsGiveDistinctTags() {
        let a = TopoTag(node: node, item: 0, role: .endCap)
        let b = TopoTag(node: node, item: 1, role: .endCap)
        #expect(a != b)
    }

    @Test func blendRolesNestEdgeKeys() {
        let key = EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .side(segment: 0))])
        let blend = TopoTag(node: NodeID(), item: 0, role: .blend(sourceEdge: key))
        #expect(blend.sortKey.contains("blend("))
    }

    @Test func seamEdgeHasTheSameFaceOnBothSides() {
        let seam = EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitZ, length: 6, midpoint: .zero,
                            convexity: .smooth, faces: [FaceID(2), FaceID(2)])
        #expect(seam.isSeam)
    }

    @Test func topologyKeyUsesAdjacentFaceTags() throws {
        let top = TopoTag(node: node, item: 0, role: .endCap)
        let side = TopoTag(node: node, item: 0, role: .side(segment: 0))
        let topology = Topology(
            faces: [
                FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
                FaceInfo(id: FaceID(1), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [side]),
            ],
            edges: [EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitY, length: 1, midpoint: .zero,
                             convexity: .convex, faces: [FaceID(0), FaceID(1)])]
        )
        let edge = try #require(topology.edge(EdgeID(0)))
        #expect(topology.key(of: edge) == EdgeKey([top], [side]))
    }

    @Test func plainLanguageFilletMessageIncludesTheLimit() {
        let error = KernelError.filletFailed(radius: 8, maxRadius: 5.9, reason: "too large")
        #expect(error.userMessage.contains("8"))
        #expect(error.userMessage.contains("5.9"))
    }
}
