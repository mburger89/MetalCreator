import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Face picks on faces a union merged (roadmap "Naming: face picks on merged faces"): `Set<TopoTag>.partsByOrigin`,
/// `Topology.resolution(of:)` and the optional keys a `FacePick` records.
struct FaceResolutionTests {
    let plate = NodeID()
    let flange = NodeID()
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }

    func face(_ id: Int, _ normal: Vector3, _ centroid: Vector3, _ tags: Set<TopoTag>) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: normal, area: 1, centroid: centroid, tags: tags)
    }

    /// The plate's left side with the flange flush: one face with both operands' tags (face 1).
    var merged: Topology {
        Topology(faces: [face(0, .unitZ, Vector3(0, 0, 6), [top]), face(1, -.unitX, Vector3(-30, 6, 8), [side, flangeSide])],
                 edges: [])
    }

    /// The flange gone elsewhere: the plate's side stands alone (face 1), and a flange face with the same tag
    /// faces the same way but stands 17 mm inboard (face 2, like a hexagon's side).
    var apart: Topology {
        Topology(faces: [
            face(0, .unitZ, Vector3(0, 0, 6), [top]), face(1, -.unitX, Vector3(-30, 0, 3), [side]),
            face(2, -.unitX, Vector3(-13, 16, 15), [flangeSide]),
        ], edges: [])
    }

    var pick: FacePick { FacePick(tags: [side, flangeSide], normal: -.unitX, centroid: Vector3(-30, 6, 8)) }

    @Test func tagsSplitByTheNodeCallThatMadeThem() {
        let parts: [Set<TopoTag>] = Set([side, flangeSide, top]).partsByOrigin
        #expect(parts.count == 2)
        #expect(Set(parts) == [[side, top], [flangeSide]])
        #expect(parts == Set([side, flangeSide, top]).partsByOrigin, "the order is stable")
    }

    @Test func tagsOfOneNodeCallDoNotSplit() {
        #expect(Set([side, top]).partsByOrigin.isEmpty)
        #expect(Set<TopoTag>().partsByOrigin.isEmpty)
        let second = TopoTag(node: plate, item: 1, role: .endCap)
        #expect(Set([top, second]).partsByOrigin.count == 2, "broadcast items are separate node calls")
    }

    @Test func aPickThatMatchesIsNotNarrowed() {
        let resolved = merged.resolution(of: pick)
        #expect(resolved == FaceResolution(faces: [merged.faces[1]]))
        #expect(!resolved.isNarrowed)
    }

    @Test func aPickOnAMergedFaceFindsThePartInItsPlane() {
        let resolved = apart.resolution(of: pick)
        #expect(resolved.faces.map(\.id) == [FaceID(1)])
        #expect(resolved.isNarrowed)
        #expect(!resolved.isAmbiguous, "the plate's side is the only part in the plane the face was in")
    }

    /// Without the normal and centroid (a pick made before they were recorded) the parts can't be told apart.
    @Test func aPickWithoutAPositionIsAGuess() {
        let resolved = apart.resolution(of: FacePick(tags: [side, flangeSide]))
        #expect(resolved.isNarrowed)
        #expect(resolved.isAmbiguous)
        #expect(resolved.faces.count == 1)
    }

    /// With no position the part is the first in `partsByOrigin` order: arbitrary (it sorts on node IDs) but the
    /// same every time, and it is the warning, not the choice, that tells the person.
    @Test func theGuessWithoutAPositionIsTheFirstPartAndStable() throws {
        let unplaced = FacePick(tags: [side, flangeSide])
        let first = try #require(unplaced.tags.partsByOrigin.first)
        let expected = apart.faces(matching: FacePick(tags: first)).map(\.id)
        #expect(apart.resolution(of: unplaced).faces.map(\.id) == expected)
        #expect(apart.resolution(of: unplaced) == apart.resolution(of: unplaced))
    }

    @Test func twoPartsInThePlaneAreAmbiguousAndTheNearestWins() {
        let coplanar = Topology(faces: [
            face(1, -.unitX, Vector3(-30, 0, 3), [side]), face(2, -.unitX, Vector3(-30, 18, 20), [flangeSide]),
        ], edges: [])
        let resolved = coplanar.resolution(of: pick)
        #expect(resolved.faces.map(\.id) == [FaceID(1)])
        #expect(resolved.isAmbiguous)
    }

    /// The plane is the same to within a micrometre: a model OCCT rebuilt can land that close without moving.
    @Test func aPartWithinAMicrometreOfThePlaneIsInIt() {
        for offset in [0.0003, -0.0009] {
            let nudged = Topology(faces: [face(1, -.unitX, Vector3(-30 + offset, 0, 3), [side])], edges: [])
            let resolved = nudged.resolution(of: pick)
            #expect(resolved.faces.map(\.id) == [FaceID(1)])
            #expect(resolved.isNarrowed && !resolved.isAmbiguous, "\(offset) mm off the plane")
        }
    }

    @Test func aPartFiveMicrometresOffThePlaneIsAGuess() {
        let moved = Topology(faces: [face(1, -.unitX, Vector3(-30.005, 0, 3), [side])], edges: [])
        #expect(moved.resolution(of: pick).isAmbiguous)
    }

    @Test func aPartOutsideThePlaneIsAGuess() {
        let moved = Topology(faces: [face(2, -.unitX, Vector3(-13, 16, 15), [flangeSide])], edges: [])
        let resolved = moved.resolution(of: pick)
        #expect(resolved.faces.map(\.id) == [FaceID(2)])
        #expect(resolved.isAmbiguous)
    }

    @Test func aPartFacingAnotherWayIsNotThePickedFace() {
        let flipped = Topology(faces: [face(2, .unitX, Vector3(-30, 16, 15), [flangeSide])], edges: [])
        #expect(flipped.resolution(of: pick) == FaceResolution(faces: []))
    }

    @Test func aPickOfOneNodeCallThatMatchesNothingStaysUnmatched() {
        let gone = FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)])
        #expect(apart.resolution(of: gone) == FaceResolution(faces: []))
        #expect(apart.resolution(of: FacePick(tags: [])) == FaceResolution(faces: []))
    }

    @Test func aFacesPickRecordsItsNormalAndCentroidWhenFlat() {
        #expect(merged.facePick(for: FaceID(1)) == pick)
        let cylinder = Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .cylinder, normal: .unitZ, area: 1, centroid: Vector3(1, 2, 3), tags: [side]),
        ], edges: [])
        #expect(cylinder.facePick(for: FaceID(0)) == FacePick(tags: [side], centroid: Vector3(1, 2, 3)))
    }

    @Test func theOptionalKeysRoundTripAndAreOmittedWhenAbsent() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try JSONDecoder().decode(FacePick.self, from: try encoder.encode(pick)) == pick)
        let plain = FacePick(tags: [side])
        let text = try #require(String(bytes: try encoder.encode(plain), encoding: .utf8))
        #expect(!text.contains("normal") && !text.contains("centroid"))
        #expect(try JSONDecoder().decode(FacePick.self, from: try encoder.encode(plain)) == plain)
    }

    /// A `FacePick` as builds before the position was recorded decode it (unknown keys ignored).
    struct EarlierFacePick: Decodable {
        var tags: [TopoTag]
    }

    @Test func anEarlierReaderIgnoresTheOptionalKeys() throws {
        let earlier = try JSONDecoder().decode(EarlierFacePick.self, from: try JSONEncoder().encode(pick))
        #expect(Set(earlier.tags) == pick.tags)
    }
}
