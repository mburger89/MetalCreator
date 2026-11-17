import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// NS-1 Task 3: the names of a sheet's boundary edges.
struct BoundaryKeyTests {
    let node = NodeID()
    var cap: TopoTag { TopoTag(node: node, item: 0, role: .startCap) }

    /// A stand-in for `NodeID.instanceScoped` (CreatorGraph): a fixed map into version-8 IDs.
    func qualify(_ node: NodeID) -> NodeID {
        var bytes = node.rawValue.uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.0 ^= 0x5A
        return NodeID(rawValue: UUID(uuid: bytes))
    }

    func boundaryTag(_ k: Int) -> TopoTag { TopoTag(node: node, item: 0, role: .boundary(.piece(loop: 0, segment: k))) }

    func edge(_ id: Int, from a: Vector3, to b: Vector3, faces: [FaceID], tags: Set<TopoTag> = []) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: (b - a).normalized, length: (b - a).length, midpoint: (a + b) * 0.5,
                 convexity: .unknown, faces: faces, curve: .line(start: a, end: b), tags: tags)
    }

    /// A sheet of one face with four boundary edges, tagged piece 0 to 3.
    var sheet: Topology {
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 20, 0), Vector3(0, 20, 0)]
        let edges = corners.indices.map { k in
            edge(k, from: corners[k], to: corners[(k + 1) % 4], faces: [FaceID(0)], tags: [boundaryTag(k)])
        }
        let face = FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 200, centroid: Vector3(5, 10, 0), tags: [cap],
                            isOnOpenShell: true)
        return Topology(faces: [face], edges: edges)
    }

    @Test func aBoundaryRoleRoundTripsThroughCodable() throws {
        let roles: [BoundaryRole] = [.start, .end, .rail(1), .piece(loop: 2, segment: 3), .imported(edge: 9)]
        for boundary in roles {
            let role = TopoRole.boundary(boundary)
            let data = try JSONEncoder().encode(role)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["role"] as? String == "boundary")
            #expect(try JSONDecoder().decode(TopoRole.self, from: data) == role)
            #expect(try JSONDecoder().decode(BoundaryRole.self, from: JSONEncoder().encode(boundary)) == boundary)
        }
    }

    @Test func sortKeysAreDistinctPerRoleAndBoundaryRolesAreStable() {
        let roles: [TopoRole] = [
            .boundary(.start), .boundary(.end), .boundary(.rail(0)), .boundary(.rail(1)),
            .boundary(.piece(loop: 0, segment: 1)), .boundary(.piece(loop: 1, segment: 0)), .boundary(.imported(edge: 1)),
            .startCap, .endCap, .imported(face: 1),
        ]
        #expect(Set(roles.map(\.sortKey)).count == roles.count)
        for role in roles { #expect(!role.isUnstable) }
    }

    @Test func aTaggedBoundaryEdgeIsNamedByItsFaceAndItsOwnTags() throws {
        let topology = sheet
        let key = try #require(topology.key(of: topology.edges[2]))
        #expect(key == EdgeKey([cap], [boundaryTag(2)]))
    }

    @Test func anUntaggedBoundaryEdgeHasNoName() {
        var topology = sheet
        topology.edges[0].tags = []
        #expect(topology.key(of: topology.edges[0]) == nil)
    }

    @Test func aBoundaryEdgeReportsItsOneFace() {
        let topology = sheet
        #expect(topology.edges.allSatisfy { $0.isBoundary })
        #expect(!topology.edges[0].isSeam)
    }

    @Test func picksIncludeATaggedBoundaryEdgeAndResolveIt() throws {
        let topology = sheet
        let picks = topology.picks(for: [EdgeID(1)])
        let pick = try #require(picks.first)
        #expect(picks.count == 1 && pick.matchCount == 1)
        #expect(topology.edges(resolving: pick.key).map(\.id) == [EdgeID(1)])
    }

    @Test func aBoundaryKeyMatchesNoOtherEdge() {
        let topology = sheet
        let key = EdgeKey([cap], [boundaryTag(1)])
        #expect(topology.edges(matching: key).map(\.id) == [EdgeID(1)])
    }

    @Test func aBoundaryEdgeIsOneRun() {
        let topology = sheet
        #expect(Topology.runCount([topology.edges[0]]) == 1)
        // Two boundary edges that meet at a corner are two runs.
        #expect(Topology.runCount([topology.edges[0], topology.edges[1]]) == 2)
    }

    @Test func aSeamIsStillSkipped() {
        var topology = sheet
        topology.edges[0].faces = [FaceID(0), FaceID(0)]
        #expect(topology.edges[0].isSeam)
        #expect(topology.picks(for: [EdgeID(0)]).isEmpty)
    }

    @Test func qualifyingACopyQualifiesItsEdgeTags() throws {
        let copy = sheet.qualified(item: 3, qualify)
        let tag = try #require(copy.edges[0].tags.first)
        #expect(tag.item == 3 && tag.node.isInstanceQualified)
        #expect(tag.role == .boundary(.piece(loop: 0, segment: 0)))
        let renamed = sheet.withInstanceItem(7)
        #expect(renamed.edges[0].tags.allSatisfy { $0.item == 7 })
    }

    @Test func aSheetIsNotClosedAndABoxIs() {
        let sheetSolid = Solid(topology: sheet, bounds: BoundingBox(min: .zero, max: Vector3(10, 20, 0)), storage: FakeStorage())
        #expect(!sheetSolid.isClosed)
        var closed = sheet
        for index in closed.edges.indices { closed.edges[index].faces = [FaceID(0), FaceID(1)] }
        #expect(Solid(topology: closed, bounds: sheetSolid.bounds, storage: FakeStorage()).isClosed)
    }
}
