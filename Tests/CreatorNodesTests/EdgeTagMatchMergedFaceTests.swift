import CreatorGeometry
import CreatorKernel
@testable import CreatorNodes
import Testing

/// Edges by Tag on faces a union merged (roadmap "Naming: picks on merged faces"), on hand-built
/// topologies shaped like the bracket's left plate side: the plate's top (face 0), its side (face 1),
/// merged with the flange's coplanar side while the flange stands flush, and a flange-only face (face 2)
/// that meets the top.
struct EdgeTagMatchMergedFaceTests {
    let plate = NodeID()
    let flange = NodeID()
    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }

    func line(_ id: Int, _ start: Vector3, _ end: Vector3, _ faces: [Int]) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: (end - start).normalized, length: (end - start).length,
                 midpoint: (start + end) * 0.5, convexity: .convex, faces: faces.map(FaceID.init),
                 curve: .line(start: start, end: end))
    }

    /// Flush (the rectangle flange): the side is merged, and the flange's fillet split its top edge at y = 12
    /// (edges 0 and 1). Apart (the hexagon): the side stands alone with one whole top edge (edge 0), and
    /// a flange face meets the top elsewhere (edge 1).
    func topology(flush: Bool) -> Topology {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero,
                     tags: flush ? [side, flangeSide] : [side]),
            FaceInfo(id: FaceID(2), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [flangeSide]),
        ]
        let edges = flush
            ? [line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6), [1, 0]), line(1, Vector3(-30, 12, 6), Vector3(-30, 15, 6), [1, 0])]
            : [line(0, Vector3(-30, 16, 6), Vector3(-30, -16, 6), [0, 1]), line(1, Vector3(-10, 12, 6), Vector3(-10, 20, 6), [0, 2])]
        return Topology(faces: faces, edges: edges)
    }

    @Test func aPickOnAMergedFaceSurvivesThePartnerLeaving() {
        let picks = topology(flush: true).picks(for: [EdgeID(0), EdgeID(1)])
        #expect(picks == [EdgePick(key: EdgeKey([top], [side, flangeSide]), matchCount: 2, runCount: 1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: false)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aPickMadeApartResolvesWhenThePartnerIsFlushAgain() {
        let picks = topology(flush: false).picks(for: [EdgeID(0)])
        #expect(picks == [EdgePick(key: EdgeKey([top], [side]), matchCount: 1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0), EdgeID(1)], warnings: []))
    }

    /// A pick saved before runs were recorded (no `runCount`) counts each recorded edge as its own run: it
    /// resolves flush without a warning, and warns as on master once the partner leaves, because its 2 recorded
    /// edges (one split edge) are now 1 run.
    @Test func aPickSavedBeforeRunsStillWarnsWhenItsEdgesBecomeFewerRuns() {
        let saved = [EdgePick(key: EdgeKey([top], [side, flangeSide]), matchCount: 2)]
        #expect(EdgeTagMatch.resolve(saved, in: topology(flush: true)).warnings == [])
        let apart = EdgeTagMatch.resolve(saved, in: topology(flush: false))
        #expect(apart.edges == [EdgeID(0)])
        #expect(apart.warnings == ["Matched 1 edge, expected 2."])
    }

    /// The other half of the rule, and a change from master (which warned "Matched 2 edges, expected 1."): a pick
    /// saved before runs were recorded, on an edge that was whole then (`matchCount` 1, no `runCount`, exactly what
    /// an older file decodes to), resolves to both pieces with no warning once the edge is split into 2 in 1 run.
    @Test func aPickSavedBeforeRunsNoLongerWarnsWhenItsEdgeIsSplit() {
        let saved = [EdgePick(key: EdgeKey([top], [side]), matchCount: 1)]
        #expect(EdgeTagMatch.resolve(saved, in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0), EdgeID(1)], warnings: []))
    }

    @Test func picksOfOnePieceStillCountEdges() {
        let picks = topology(flush: true).picks(for: [EdgeID(1)])
        #expect(picks.first?.ordinals == [1])
        let apart = EdgeTagMatch.resolve(picks, in: topology(flush: false))
        #expect(apart.warnings == ["Matched 1 edge, expected 2."])
    }
}
