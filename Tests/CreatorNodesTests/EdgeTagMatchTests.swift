import CreatorGeometry
import CreatorKernel
@testable import CreatorNodes
import Testing

struct EdgeTagMatchTests {
    let node = NodeID()
    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var front: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 0)) }
    var right: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 1)) }

    /// Top face 0, front face 1, right face 2. Edges 0 and 1 share {top, front} (x = 5 and x = −5);
    /// edge 2 is {top, right}.
    func topology(splitFront: Bool = true) -> Topology {
        var edges = [
            EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitX, length: 4, midpoint: Vector3(5, -5, 10),
                     convexity: .convex, faces: [FaceID(0), FaceID(1)]),
            EdgeInfo(id: EdgeID(2), kind: .line, direction: .unitY, length: 10, midpoint: Vector3(15, 0, 10),
                     convexity: .convex, faces: [FaceID(0), FaceID(2)]),
        ]
        if splitFront {
            edges.append(EdgeInfo(id: EdgeID(1), kind: .line, direction: .unitX, length: 4, midpoint: Vector3(-5, -5, 10),
                                  convexity: .convex, faces: [FaceID(1), FaceID(0)]))
        }
        return Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitY, area: 1, centroid: .zero, tags: [front]),
            FaceInfo(id: FaceID(2), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [right]),
        ], edges: edges)
    }

    @Test func picksResolveWithoutWarnings() {
        let picks = topology().picks(for: [EdgeID(2), EdgeID(0), EdgeID(1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology()) == EdgeTagMatch(edges: [EdgeID(2), EdgeID(1), EdgeID(0)], warnings: []))
    }

    @Test func ordinalsSelectThePickedOneOfSeveral() {
        let picks = topology().picks(for: [EdgeID(0)])
        #expect(EdgeTagMatch.resolve(picks, in: topology()).edges == [EdgeID(0)])
    }

    @Test func aChangedMatchCountWarnsButStillSelects() {
        let picks = topology(splitFront: false).picks(for: [EdgeID(0)])
        let match = EdgeTagMatch.resolve(picks, in: topology())
        #expect(match.edges == [EdgeID(1), EdgeID(0)])
        #expect(match.warnings == ["Matched 2 edges, expected 1."])
    }

    @Test func zeroMatchesWarn() {
        let picks = [EdgePick(key: EdgeKey([top], [TopoTag(node: NodeID(), item: 0, role: .startCap)]), matchCount: 1)]
        #expect(EdgeTagMatch.resolve(picks, in: topology()) == EdgeTagMatch(edges: [], warnings: ["Matched 0 edges, expected 1."]))
    }

    /// A 1 → 2 drift and a 1 → 0 drift must not add up to "Matched 2 edges, expected 2.".
    @Test func oppositeDriftsDoNotCancelOut() {
        let split = EdgePick(key: EdgeKey([top], [front]), matchCount: 1)
        let gone = EdgePick(key: EdgeKey([top], [TopoTag(node: NodeID(), item: 0, role: .startCap)]), matchCount: 1)
        let match = EdgeTagMatch.resolve([split, gone], in: topology())
        #expect(match.edges == [EdgeID(1), EdgeID(0)])
        #expect(match.warnings == ["Matched 2 edges, expected 1; 0 edges, expected 1."])
    }

    @Test func noPicksAsksForAPick() {
        #expect(EdgeTagMatch.resolve([], in: topology()).warnings == [EdgeTagMatch.nothingPicked])
    }

    @Test func unnamedPicksWarnEvenWhenTheyMatch() {
        let unnamed = TopoTag(node: node, item: 0, role: .unnamed(face: 1))
        var shaky = topology()
        shaky.faces[1].tags = [unnamed]
        let picks = shaky.picks(for: [EdgeID(2)]) + shaky.picks(for: [EdgeID(0), EdgeID(1)])
        let match = EdgeTagMatch.resolve(picks, in: shaky)
        #expect(match.edges.count == 3)
        #expect(match.warnings == [EdgeTagMatch.unnamedPick])
    }

    @Test func overlappingPicksDoNotDuplicateEdges() {
        let both = EdgePick(key: EdgeKey([top], [front]), matchCount: 2)
        let one = EdgePick(key: EdgeKey([top], [front]), matchCount: 2, ordinals: [1])
        #expect(EdgeTagMatch.resolve([both, one], in: topology()).edges == [EdgeID(1), EdgeID(0)])
    }
}
