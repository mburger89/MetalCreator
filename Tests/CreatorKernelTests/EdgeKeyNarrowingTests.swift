import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Picks on faces a union merged (roadmap "Naming: picks on merged faces"): `EdgeKey.narrowed` and
/// `Topology.edges(resolving:)`.
struct EdgeKeyNarrowingTests {
    let plate = NodeID()
    let flange = NodeID()

    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var flangeFront: TopoTag { TopoTag(node: flange, item: 0, role: .endCap) }

    @Test func aMergedSideNarrowsToTheOperandTheOtherSideCameFrom() {
        #expect(EdgeKey([top], [side, flangeSide]).narrowed == EdgeKey([top], [side]))
        #expect(EdgeKey([side, flangeSide], [top]).narrowed == EdgeKey([top], [side]))
    }

    @Test func aKeyOfOneOperandIsNotNarrowed() {
        #expect(EdgeKey([top], [side]).narrowed == nil)
    }

    /// The plate's top against the flange's front face: the edge where two operands meet keeps its name.
    @Test func anEdgeWhereTwoOperandsMeetIsNotNarrowed() {
        #expect(EdgeKey([top], [flangeFront]).narrowed == nil)
    }

    @Test func aKeyWhoseSidesAreBothMergedFromTheSameOperandsIsNotNarrowed() {
        let flangeTop = TopoTag(node: flange, item: 0, role: .side(segment: 2))
        #expect(EdgeKey([top, flangeTop], [side, flangeSide]).narrowed == nil)
    }

    /// Broadcast items are separate node calls: the faces of item 1 are not item 0's.
    @Test func anotherBroadcastItemOfTheSameNodeIsAnotherOperand() {
        let secondSide = TopoTag(node: plate, item: 1, role: .side(segment: 6))
        #expect(EdgeKey([top], [side, secondSide]).narrowed == EdgeKey([top], [side]))
    }

    /// Face 0: top. Face 1: the plate's side, merged with the flange's (`merged`) or on its own. Face 2: a
    /// face carrying the flange tag the pick also names (the hexagon's side 3 standing on the plate after the
    /// swap). Edge 0 is top | face 1; edge 1 is top | face 2.
    func topology(merged: Bool) -> Topology {
        Topology(
            faces: [
                FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
                FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero,
                         tags: merged ? [side, flangeSide] : [side]),
                FaceInfo(id: FaceID(2), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            ],
            edges: [
                EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitY, length: 32, midpoint: Vector3(-30, 0, 6),
                         convexity: .convex, faces: [FaceID(0), FaceID(1)]),
                EdgeInfo(id: EdgeID(1), kind: .line, direction: .unitY, length: 8, midpoint: Vector3(-10, 16, 6),
                         convexity: .concave, faces: [FaceID(0), FaceID(2)]),
            ]
        )
    }

    @Test func aKeyThatMatchesResolvesToItsMatches() {
        let key = EdgeKey([top], [side, flangeSide])
        #expect(topology(merged: true).edges(resolving: key).map(\.id) == [EdgeID(0)])
        // The narrowed key would match edge 0 too; a key that matches is never narrowed, so nothing changes.
        #expect(topology(merged: true).edges(resolving: EdgeKey([top], [side])).map(\.id) == [EdgeID(0)])
    }

    @Test func aPickOnAMergedFaceFindsItsEdgeWhenThePartnerLeaves() {
        let key = EdgeKey([top], [side, flangeSide])
        #expect(topology(merged: false).edges(matching: key).isEmpty)
        #expect(topology(merged: false).edges(resolving: key).map(\.id) == [EdgeID(0)])
    }

    /// The flange's tag alone is not enough: the edge between the top and a flange-only face is not the one
    /// that was picked.
    @Test func theOtherOperandsTagAloneDoesNotMatch() {
        let resolved = topology(merged: false).edges(resolving: EdgeKey([top], [side, flangeSide]))
        #expect(!resolved.contains { $0.id == EdgeID(1) })
    }

    @Test func aKeyThatCantBeNarrowedStillMatchesNothing() {
        let gone = TopoTag(node: NodeID(), item: 0, role: .startCap)
        #expect(topology(merged: false).edges(resolving: EdgeKey([top], [gone])).isEmpty)
    }
}
