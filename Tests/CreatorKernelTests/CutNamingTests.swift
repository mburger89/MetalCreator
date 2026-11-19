import CreatorGeometry
import Foundation
import Testing
@testable import CreatorKernel

/// NS-4 Task 3: cut names (R2), the nested tags they carry, the kernel's refusing defaults and R17's `RegionPick`.
struct CutNamingTests {
    let node = NodeID()
    let other = NodeID()

    private func tag(_ id: NodeID, _ role: TopoRole, item: Int = 0) -> TopoTag { TopoTag(node: id, item: item, role: role) }

    @Test func cutSideRoundTrips() throws {
        let first = TopoRole.cutSide(.curve(index: 1, piece: 2), .inside)
        let a = tag(other, .startCap), b = tag(other, .endCap)
        let second = TopoRole.cutSide(.face([a, b]), .front)
        for role in [first, second] {
            #expect(try JSONDecoder().decode(TopoRole.self, from: JSONEncoder().encode(role)) == role)
        }
        #expect(first.sortKey == "cutSide(curve(1:2):inside)")
        let expected = [a, b].map(\.sortKey).sorted().joined(separator: "+")
        #expect(second.sortKey == "cutSide(face(\(expected)):front)")
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        #expect(object["role"] as? String == "cutSide" && object["side"] as? String == "inside")
    }

    @Test func cutEdgeRoundTrips() throws {
        let role = TopoRole.boundary(.cut(.curve(index: 0, piece: 0)))
        #expect(try JSONDecoder().decode(TopoRole.self, from: JSONEncoder().encode(role)) == role)
        #expect(role.sortKey == "boundary(cut(curve(0:0)))")
        let faceCut = TopoRole.boundary(.cut(.face([tag(other, .startCap)])))
        #expect(try JSONDecoder().decode(TopoRole.self, from: JSONEncoder().encode(faceCut)) == faceCut)
        let json = try #require(String(bytes: JSONEncoder().encode(BoundaryRole.cut(.curve(index: 3, piece: 4))), encoding: .utf8))
        #expect(json.contains("\"cutter\"") && json.contains("\"cut\""))
    }

    @Test func cutterNameJSONShape() throws {
        let name = CutterName.face([tag(other, .endCap), tag(other, .startCap)])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(name)) as? [String: Any])
        #expect(object["kind"] as? String == "face")
        let tags = try #require(object["tags"] as? [[String: Any]])
        #expect(tags.count == 2)
        let curveData = try JSONEncoder().encode(CutterName.curve(index: 2, piece: 5))
        let curve = try #require(try JSONSerialization.jsonObject(with: curveData) as? [String: Any])
        #expect(curve["kind"] as? String == "curve" && curve["index"] as? Int == 2 && curve["piece"] as? Int == 5)
        #expect(CutterName.curve(index: 2, piece: 5).sortKey == "curve(2:5)")
    }

    @Test func nestedTagsAreRenamed() {
        let inner = tag(other, .side(segment: 1), item: 0)
        let role = TopoRole.cutSide(.face([inner]), .front)
        let renumbered = tag(node, role).withItem(5)
        guard case .cutSide(.face(let tags), .front) = renumbered.role else { Issue.record("shape"); return }
        #expect(tags.map(\.item) == [5] && renumbered.item == 5)

        let edge = tag(node, .boundary(.cut(.face([inner])))).withItem(7)
        guard case .boundary(.cut(.face(let edgeTags))) = edge.role else { Issue.record("shape"); return }
        #expect(edgeTags.map(\.item) == [7])

        let qualified = tag(node, role).qualified(item: 3) { _ in self.node }
        guard case .cutSide(.face(let qualifiedTags), _) = qualified.role else { Issue.record("shape"); return }
        #expect(qualifiedTags.map(\.node) == [node] && qualifiedTags.map(\.item) == [3])

        #expect(role.nestedTags == [inner])
        #expect(TopoRole.cutSide(.curve(index: 0, piece: 0), .back).nestedTags.isEmpty)
        #expect(TopoTag.instanceTags(in: [tag(node, role)]).isEmpty)

        var bytes = UUID().uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        let instanceNode = NodeID(rawValue: UUID(uuid: bytes))
        #expect(instanceNode.isInstanceQualified)
        let nested = tag(instanceNode, .side(segment: 0), item: 4)
        #expect(TopoTag.instanceTags(in: [tag(node, .cutSide(.face([nested]), .front))]) == [nested])
        #expect(TopoTag.instanceTags(in: [tag(node, .boundary(.cut(.face([nested]))))]) == [nested])
    }

    @Test func unstableNestedTagsAreUnstable() {
        #expect(TopoRole.cutSide(.face([tag(other, .unnamed(face: 2))]), .front).isUnstable)
        #expect(TopoRole.boundary(.cut(.face([tag(other, .unnamed(face: 2))]))).isUnstable)
        #expect(!TopoRole.cutSide(.face([tag(other, .startCap)]), .front).isUnstable)
        #expect(!TopoRole.cutSide(.curve(index: 0, piece: 0), .front).isUnstable)
    }

    @Test func regionPickJSON() throws {
        let pick = FacePick(tags: [tag(node, .startCap)], normal: Vector3(0, 0, 1), centroid: Vector3(1, 2, 3))
        let single = RegionPick(pick: pick, sharedBy: 1)
        let singleObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(single)) as? [String: Any])
        #expect(singleObject["sharedBy"] == nil && singleObject["pick"] != nil)
        #expect(try JSONDecoder().decode(RegionPick.self, from: JSONEncoder().encode(single)) == single)
        let shared = RegionPick(pick: pick, sharedBy: 2)
        let sharedObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(shared)) as? [String: Any])
        #expect(sharedObject["sharedBy"] as? Int == 2)
        #expect(try JSONDecoder().decode(RegionPick.self, from: JSONEncoder().encode(shared)) == shared)
        #expect(RegionPick(pick: pick, sharedBy: 0).sharedBy == 1)
    }

    @Test func fakeKernelRefusesTheNewCalls() async throws {
        let kernel = FakeKernel()
        let tag = NodeTag(node: node, item: 0)
        let box = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
        let curve = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(1, 0, 0))], tag: tag)
        let end = SurfaceBlendEnd(body: box, edge: EdgeID(0), continuity: .g1, bulge: 1)
        await #expect(throws: KernelError.unsupported("splitting surfaces")) {
            _ = try await kernel.split(box, by: .curves([curve], projection: .alongDirection, direction: .unitZ), tag: tag)
        }
        await #expect(throws: KernelError.unsupported("keeping faces of a sheet")) {
            _ = try await kernel.subSheet([FaceID(0)], of: box)
        }
        await #expect(throws: KernelError.unsupported("intersecting bodies")) {
            _ = try await kernel.intersectionCurves(box, box, tag: tag)
        }
        await #expect(throws: KernelError.unsupported("extending surfaces")) {
            _ = try await kernel.extended(box, edges: [EdgeID(0)], length: 1, mode: .natural)
        }
        await #expect(throws: KernelError.unsupported("matching surfaces")) {
            _ = try await kernel.matched(box, edge: EdgeID(0), to: EdgeID(1), of: box, continuity: .g1)
        }
        await #expect(throws: KernelError.unsupported("blending surfaces")) { _ = try await kernel.blendSurface(end, end, tag: tag) }
    }
}
