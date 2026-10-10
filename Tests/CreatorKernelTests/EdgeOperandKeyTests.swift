import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Edge picks between a merged face and a third operand's face (roadmap "Naming: face picks on merged faces"):
/// `EdgeKey.operandKeys` and `Topology.resolution(of:expecting:)`.
struct EdgeOperandKeyTests {
    let plate = NodeID()
    let flange = NodeID()
    let hole = NodeID()
    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var flangeFront: TopoTag { TopoTag(node: flange, item: 0, role: .endCap) }
    var wall: TopoTag { TopoTag(node: hole, item: 0, role: .side(segment: 0)) }

    @Test func aMergedSideSharingNothingWithTheOtherSideIsSplitByOperand() {
        let keys = EdgeKey([side, flangeSide], [wall]).operandKeys
        #expect(Set(keys) == [EdgeKey([side], [wall]), EdgeKey([flangeSide], [wall])])
        #expect(keys == EdgeKey([wall], [flangeSide, side]).operandKeys, "the order is stable")
    }

    @Test func twoMergedSidesAreSplitOnBothSides() {
        let otherWall = TopoTag(node: NodeID(), item: 0, role: .side(segment: 1))
        #expect(Set(EdgeKey([side, flangeSide], [wall, otherWall]).operandKeys).count == 4, "each operand against each")
    }

    /// A side that has a node call in common with the other side is `narrowed`'s case, not this one's.
    @Test func aSideSharingANodeCallWithTheOtherSideIsNotSplit() {
        #expect(EdgeKey([top], [side, flangeSide]).operandKeys.isEmpty)
        #expect(EdgeKey([top, flangeFront], [side, flangeSide]).operandKeys.isEmpty)
    }

    @Test func aKeyOfSingleOperandSidesHasNoOperandKeys() {
        #expect(EdgeKey([side], [wall]).operandKeys.isEmpty)
    }

    /// Face 0: the plate's side, with or without the flange's tag (`merged`). Face 1: a flange face of its own.
    /// Face 2: the hole's wall. Edge 0 is the hole's rim on the plate part (face 0 | wall); `flangeRims` more
    /// edges (IDs 1...) are rims on the flange part (face 1 | wall).
    func topology(merged: Bool, flangeRims: Int = 0) -> Topology {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: merged ? [side, flangeSide] : [side]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            FaceInfo(id: FaceID(2), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero, tags: [wall]),
        ]
        func rim(_ id: Int, _ face: Int, at z: Double) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitX, length: 15, midpoint: Vector3(-30, 16, z),
                     convexity: .concave, faces: [FaceID(face), FaceID(2)])
        }
        let flange = (0..<flangeRims).map { rim($0 + 1, 1, at: 12 + 8 * Double($0)) }
        return Topology(faces: faces, edges: [rim(0, 0, at: 3)] + flange)
    }

    @Test func aKeyThatMatchesIsResolvedAsBefore() {
        let key = EdgeKey([side, flangeSide], [wall])
        let merged = topology(merged: true)
        #expect(merged.resolution(of: key) == EdgeResolution(edges: [merged.edges[0]]))
    }

    @Test func aRimOnAMergedSideIsFoundOnTheOperandThatStillHasIt() {
        let key = EdgeKey([side, flangeSide], [wall])
        let apart = topology(merged: false)
        #expect(apart.edges(matching: key).isEmpty)
        #expect(apart.resolution(of: key, expecting: 1) == EdgeResolution(edges: [apart.edges[0]], isSplit: true))
        #expect(apart.edges(resolving: key).map(\.id) == [EdgeID(0)])
    }

    @Test func twoOperandsWithARimAreAmbiguousUnlessTheCountTellsThemApart() {
        let key = EdgeKey([side, flangeSide], [wall])
        let both = topology(merged: false, flangeRims: 1)
        let guess = both.resolution(of: key, expecting: 1)
        #expect(guess.isAmbiguous && guess.isSplit)
        #expect(guess.edges.count == 1, "one operand's rim, never both")
        #expect(both.resolution(of: key).isAmbiguous)
        #expect(both.resolution(of: key, expecting: 5).isAmbiguous, "no operand has five")
    }

    @Test func theCountPicksTheOperandWhoseRimsMatchIt() {
        // The flange's face has two rims; the plate's has one. A pick of two edges was the flange's.
        let two = topology(merged: false, flangeRims: 2).resolution(of: EdgeKey([side, flangeSide], [wall]), expecting: 2)
        #expect(!two.isAmbiguous && two.isSplit)
        #expect(two.edges.map(\.id) == [EdgeID(1), EdgeID(2)])
    }

    @Test func aKeyOfGoneTagsStillMatchesNothing() {
        let gone = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let key = EdgeKey([side, gone], [TopoTag(node: NodeID(), item: 0, role: .endCap)])
        #expect(topology(merged: false).resolution(of: key) == EdgeResolution(edges: []))
    }
}
