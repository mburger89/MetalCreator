import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct EdgePickTests {
    let node = NodeID()
    let other = NodeID()

    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var front: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 0)) }
    var right: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 1)) }
    var flange: TopoTag { TopoTag(node: other, item: 0, role: .side(segment: 3)) }

    /// Face 0: top. Face 1: front. Face 2: right, merged with a flange face by a union.
    /// Edges 0 and 1 share the key {top, front} (a cut split the front edge in two);
    /// edge 2 borders the merged face; edge 3 is a seam on the front face.
    func sample() -> Topology {
        Topology(
            faces: [
                FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
                FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitY, area: 1, centroid: .zero, tags: [front]),
                FaceInfo(id: FaceID(2), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [right, flange]),
            ],
            edges: [
                EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitX, length: 4, midpoint: Vector3(5, -5, 10),
                         convexity: .convex, faces: [FaceID(0), FaceID(1)]),
                EdgeInfo(id: EdgeID(1), kind: .line, direction: .unitX, length: 4, midpoint: Vector3(-5, -5, 10),
                         convexity: .convex, faces: [FaceID(1), FaceID(0)]),
                EdgeInfo(id: EdgeID(2), kind: .line, direction: .unitY, length: 10, midpoint: Vector3(15, 0, 10),
                         convexity: .convex, faces: [FaceID(0), FaceID(2)]),
                EdgeInfo(id: EdgeID(3), kind: .line, direction: .unitZ, length: 10, midpoint: Vector3(0, -5, 5),
                         convexity: .smooth, faces: [FaceID(1), FaceID(1)]),
            ]
        )
    }

    @Test func keySidesMatchAsSubsetsInEitherOrder() throws {
        let topology = sample()
        let merged = try #require(topology.edge(EdgeID(2)))
        #expect(topology.edge(merged, matches: EdgeKey([top], [right])))
        #expect(topology.edge(merged, matches: EdgeKey([right], [top])))
        #expect(topology.edge(merged, matches: EdgeKey([top], [right, flange])))
    }

    @Test func aPickedTagTheFaceLacksDoesNotMatch() throws {
        let topology = sample()
        let merged = try #require(topology.edge(EdgeID(2)))
        #expect(!topology.edge(merged, matches: EdgeKey([top], [front])))
        #expect(!topology.edge(merged, matches: EdgeKey([top], [right, front])))
    }

    @Test func seamsNeverMatch() throws {
        let topology = sample()
        let seam = try #require(topology.edge(EdgeID(3)))
        #expect(!topology.edge(seam, matches: EdgeKey([front], [front])))
    }

    @Test func matchesAreOrderedByMidpoint() {
        #expect(sample().edges(matching: EdgeKey([top], [front])).map(\.id) == [EdgeID(1), EdgeID(0)])
    }

    @Test func pickingEveryMatchStoresNoOrdinals() {
        let picks = sample().picks(for: [EdgeID(0), EdgeID(1)])
        #expect(picks == [EdgePick(key: EdgeKey([top], [front]), matchCount: 2, ordinals: nil)])
    }

    @Test func pickingOneOfSeveralMatchesStoresItsOrdinal() {
        // Edge 0 has the larger x midpoint, so it is second (ordinal 1) in midpoint order.
        let picks = sample().picks(for: [EdgeID(0)])
        #expect(picks == [EdgePick(key: EdgeKey([top], [front]), matchCount: 2, ordinals: [1])])
    }

    @Test func seamsAndUnknownEdgesAreNotPicked() {
        #expect(sample().picks(for: [EdgeID(3), EdgeID(99)]).isEmpty)
    }

    @Test func unnamedTagsAreDetected() {
        let unnamed = TopoTag(node: node, item: 0, role: .unnamed(face: 4))
        #expect(EdgePick(key: EdgeKey([top], [unnamed]), matchCount: 1).touchesUnnamedFace)
        #expect(!EdgePick(key: EdgeKey([top], [front]), matchCount: 1).touchesUnnamedFace)
        // A blend face made from an edge that bordered an unnamed face is just as unstable.
        let shakyBlend = TopoTag(node: other, item: 0, role: .blend(sourceEdge: EdgeKey([top], [unnamed])))
        let stableBlend = TopoTag(node: other, item: 0, role: .blend(sourceEdge: EdgeKey([top], [front])))
        #expect(EdgePick(key: EdgeKey([top], [shakyBlend]), matchCount: 1).touchesUnnamedFace)
        #expect(!EdgePick(key: EdgeKey([top], [stableBlend]), matchCount: 1).touchesUnnamedFace)
    }

    @Test func picksRoundTripThroughJSON() throws {
        let picks = [EdgePick(key: EdgeKey([top], [front]), matchCount: 2, ordinals: [1]),
                     EdgePick(key: EdgeKey([top], [right, flange]), matchCount: 1),
        ]
        let decoded = try JSONDecoder().decode([EdgePick].self, from: try JSONEncoder().encode(picks))
        #expect(decoded == picks)
    }
}
