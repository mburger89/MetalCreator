import Foundation
import Testing
@testable import CreatorKernel

struct TopoRoleLoopTests {
    @Test func sideWithoutALoopIsAnOuterWall() {
        #expect(TopoRole.side(segment: 3) == .side(loop: 0, segment: 3))
        #expect(TopoRole.side(segment: 3) != .side(loop: 1, segment: 3))
    }

    @Test func outerWallSortKeysAreUnchanged() {
        #expect(TopoRole.side(segment: 3).sortKey == "side(3)")
        #expect(TopoRole.side(loop: 0, segment: 12).sortKey == "side(12)")
    }

    @Test func holeWallSortKeysNameTheLoop() {
        #expect(TopoRole.side(loop: 1, segment: 3).sortKey == "side(1:3)")
        #expect(TopoRole.side(loop: 1, segment: 3).sortKey != TopoRole.side(loop: 13, segment: 0).sortKey)
        #expect(TopoRole.side(loop: 1, segment: 3).sortKey != TopoRole.side(segment: 13).sortKey)
    }

    func json(_ role: TopoRole) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try #require(String(bytes: try encoder.encode(role), encoding: .utf8))
    }

    @Test func outerWallsEncodeWithoutALoop() throws {
        #expect(try json(.side(segment: 2)) == #"{"role":"side","segment":2}"#)
    }

    @Test func holeWallsEncodeTheirLoop() throws {
        #expect(try json(.side(loop: 2, segment: 1)) == #"{"loop":2,"role":"side","segment":1}"#)
    }

    @Test(arguments: [TopoRole.side(loop: 1, segment: 0), .side(loop: 3, segment: 7), .side(segment: 4)])
    func sideRolesRoundTrip(_ role: TopoRole) throws {
        #expect(try JSONDecoder().decode(TopoRole.self, from: try JSONEncoder().encode(role)) == role)
    }

    @Test func aMissingLoopDecodesAsTheOuterLoop() throws {
        let role = try JSONDecoder().decode(TopoRole.self, from: Data(#"{"role":"side","segment":2}"#.utf8))
        #expect(role == .side(loop: 0, segment: 2))
    }

    @Test func aNegativeLoopIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TopoRole.self, from: Data(#"{"role":"side","loop":-1,"segment":2}"#.utf8))
        }
    }

    /// `.side(loop: -1, ...)` can be built, but decoding refuses it, so encoding must too: a file that can't be read back
    /// is never written. Only the OCCT tagger makes side roles, and its loops are never negative.
    @Test func aNegativeLoopIsNotEncoded() {
        #expect(throws: EncodingError.self) { try JSONEncoder().encode(TopoRole.side(loop: -1, segment: 2)) }
    }

    @Test func anOldEdgePickDecodesWithOuterWalls() throws {
        let node = NodeID()
        let json = """
        {"key": {"first": [{"node": "\(node.rawValue.uuidString)", "item": 0, "role": {"role": "endCap"}}],
                 "second": [{"node": "\(node.rawValue.uuidString)", "item": 0, "role": {"role": "side", "segment": 2}}]},
         "matchCount": 1}
        """
        let pick = try JSONDecoder().decode(EdgePick.self, from: Data(json.utf8))
        let wall = TopoTag(node: node, item: 0, role: .side(loop: 0, segment: 2))
        #expect(pick.key == EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [wall]))
    }

    @Test func aBlendOfAHoleRimRoundTrips() throws {
        let node = NodeID()
        let rim = EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .side(loop: 1, segment: 0))])
        let role = TopoRole.blend(sourceEdge: rim)
        let decoded = try JSONDecoder().decode(TopoRole.self, from: try JSONEncoder().encode(role))
        #expect(decoded == role)
        #expect(decoded.sortKey == role.sortKey)
    }
}
