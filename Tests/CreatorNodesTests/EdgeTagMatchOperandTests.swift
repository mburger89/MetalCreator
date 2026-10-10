import CreatorGeometry
import CreatorKernel
@testable import CreatorNodes
import Testing

/// Edges by Tag on a hole's rim through a face a union merged (roadmap "Naming: face picks on merged faces"), on
/// hand-built topologies: the plate's side (face 0), merged with the flange's coplanar side while the flange
/// stands flush, a flange face of its own (face 1) and the hole's wall (face 2).
struct EdgeTagMatchOperandTests {
    let plate = NodeID()
    let flange = NodeID()
    let hole = NodeID()
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var wall: TopoTag { TopoTag(node: hole, item: 0, role: .side(segment: 0)) }

    func rim(_ id: Int, _ face: Int, at z: Double) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitX, length: 15, midpoint: Vector3(-30, 16, z),
                 convexity: .concave, faces: [FaceID(face), FaceID(2)])
    }

    func topology(flush: Bool, flangeRim: Bool = false) -> Topology {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: flush ? [side, flangeSide] : [side]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            FaceInfo(id: FaceID(2), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero, tags: [wall]),
        ]
        return Topology(faces: faces, edges: flangeRim ? [rim(0, 0, at: 3), rim(1, 1, at: 12)] : [rim(0, 0, at: 3)])
    }

    @Test func aRimPickedOnTheMergedSideSurvivesTheFlangeLeaving() {
        let picks = topology(flush: true).picks(for: [EdgeID(0)])
        #expect(picks == [EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: false)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aRimPickedApartResolvesWhenTheFlangeIsFlushAgain() {
        let picks = topology(flush: false).picks(for: [EdgeID(0)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aGuessBetweenOperandsIsReportedNotSilent() {
        let picks = topology(flush: true).picks(for: [EdgeID(0)])
        let match = EdgeTagMatch.resolve(picks, in: topology(flush: false, flangeRim: true))
        #expect(match.edges.count == 1)
        #expect(match.warnings == [EdgeTagMatch.ambiguousPick])
    }

    /// The recorded count is one solid's; a sum over several references is nobody's, so `choose` can be told not
    /// to compare it. The flange's face has two rims and the plate's one, and the pick recorded two.
    @Test func aCountSummedOverReferencesIsNotComparedWithOneSolid() {
        let flangeRims = Topology(faces: topology(flush: false).faces,
                                  edges: [rim(0, 0, at: 3), rim(1, 1, at: 12), rim(2, 1, at: 20)])
        let pick = EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 2)
        let compared = EdgeTagMatch.choose(pick, in: flangeRims)
        #expect(!compared.isAmbiguous && compared.chosen.map(\.id) == [EdgeID(1), EdgeID(2)])
        #expect(EdgeTagMatch.choose(pick, in: flangeRims, comparesRecordedCount: false).isAmbiguous)
    }

    /// Ordinals index the edges the whole key matched; once the key has been split by operand they index another
    /// list, so the pick says it guessed, even with one operand left. A key that still matches isn't split.
    @Test func anOrdinalPickResolvedByOperandIsAGuess() {
        let pick = EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 1, ordinals: [0])
        let apart = EdgeTagMatch.resolve([pick], in: topology(flush: false))
        #expect(apart.edges == [EdgeID(0)])
        #expect(apart.warnings == [EdgeTagMatch.ambiguousPick])
        #expect(EdgeTagMatch.resolve([pick], in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aRimThatIsGoneWarnsAsBefore() {
        let picks = topology(flush: true).picks(for: [EdgeID(0)])
        let bare = Topology(faces: topology(flush: false).faces, edges: [])
        #expect(EdgeTagMatch.resolve(picks, in: bare).warnings == ["Matched 0 edges, expected 1."])
    }
}
