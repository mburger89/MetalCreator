import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// S4: the face pick a Plane from Face node remembers (sketcher spec §7).
struct FacePickTests {
    let node = NodeID()
    let other = NodeID()

    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var bottom: TopoTag { TopoTag(node: node, item: 0, role: .startCap) }
    var flangeTop: TopoTag { TopoTag(node: other, item: 0, role: .endCap) }

    /// Face 0: bottom. Face 1: top, merged with a coplanar flange top by a union. Face 2: the flange top again
    /// (a cut split it off).
    func sample() -> Topology {
        Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitZ, area: 1, centroid: .zero, tags: [bottom]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top, flangeTop]),
            FaceInfo(id: FaceID(2), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [flangeTop]),
        ], edges: [])
    }

    @Test func aPickMatchesEveryFaceWhoseTagsIncludeItsOwn() {
        #expect(sample().faces(matching: FacePick(tags: [top])).map(\.id) == [FaceID(1)])
        #expect(sample().faces(matching: FacePick(tags: [flangeTop])).map(\.id) == [FaceID(1), FaceID(2)])
        #expect(sample().faces(matching: FacePick(tags: [top, bottom])).isEmpty)
    }

    @Test func anEmptyPickMatchesNothing() {
        #expect(sample().faces(matching: FacePick(tags: [])).isEmpty)
    }

    @Test func aFacesPickIsItsWholeTagSet() {
        #expect(sample().facePick(for: FaceID(1))?.tags == [top, flangeTop])
        #expect(sample().facePick(for: FaceID(9)) == nil)
    }

    @Test func picksRoundTripAndEncodeDeterministically() throws {
        let pick = FacePick(tags: [top, flangeTop, bottom])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pick)
        #expect(try JSONDecoder().decode(FacePick.self, from: data) == pick)
        let reordered = FacePick(tags: Set([bottom, flangeTop, top].reversed()))
        #expect(try encoder.encode(reordered) == data)
    }

    @Test func aPickOnAnUnnamedOrBlendOfUnnamedFaceIsUnstable() {
        let unnamed = TopoTag(node: node, item: 0, role: .unnamed(face: 4))
        let blend = TopoTag(node: other, item: 0, role: .blend(sourceEdge: EdgeKey([top], [unnamed])))
        #expect(!FacePick(tags: [top]).touchesUnnamedFace)
        #expect(FacePick(tags: [unnamed]).touchesUnnamedFace)
        #expect(FacePick(tags: [blend]).touchesUnnamedFace)
    }
}
