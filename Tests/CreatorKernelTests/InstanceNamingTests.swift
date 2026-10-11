import CreatorGeometry
import Foundation
import Testing
@testable import CreatorKernel

/// Patterns spec §6: a placed copy's tags are its tool's tags qualified by the instance, and a pick on an instance
/// that is gone is told apart from one that merely matches nothing.
struct InstanceNamingTests {
    let tool = NodeID()
    let place = NodeID()

    /// A stand-in for `NodeID.instanceScoped([place, node])` (CreatorGraph): a fixed map into version-8 IDs.
    func qualify(_ node: NodeID) -> NodeID {
        var bytes = node.rawValue.uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.0 ^= 0x5A
        return NodeID(rawValue: UUID(uuid: bytes))
    }

    func wall(_ node: NodeID, item: Int = 0) -> TopoTag { TopoTag(node: node, item: item, role: .side(segment: 1)) }

    func face(_ id: Int, _ tags: Set<TopoTag>) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .cylinder, normal: nil, area: 1, centroid: .zero, tags: tags)
    }

    @Test func onlyVersionEightIDsAreInstanceQualified() {
        #expect(!NodeID().isInstanceQualified)
        #expect(qualify(tool).isInstanceQualified)
        #expect(!tool.isInstanceQualified)
    }

    @Test func aTagIsRequalifiedByNodeAndItem() {
        let tag = wall(tool, item: 4).qualified(item: 7, qualify)
        #expect(tag == TopoTag(node: qualify(tool), item: 7, role: .side(segment: 1)))
    }

    @Test func aBlendTagRequalifiesItsSourceEdge() {
        let key = EdgeKey([wall(tool)], [TopoTag(node: tool, item: 0, role: .endCap)])
        let blend = TopoTag(node: tool, item: 0, role: .blend(sourceEdge: key))
        let moved = blend.qualified(item: 3, qualify)
        let expected = EdgeKey([wall(qualify(tool), item: 3)], [TopoTag(node: qualify(tool), item: 3, role: .endCap)])
        #expect(moved.role == .blend(sourceEdge: expected))
        #expect(moved.node == qualify(tool))
    }

    @Test func aTopologyKeepsItsShapeAndRenamesItsFaces() {
        let edge = EdgeInfo(id: EdgeID(0), kind: .circle, direction: .unitZ, length: 3, midpoint: .zero, convexity: .convex,
                            faces: [FaceID(0), FaceID(1)])
        let topology = Topology(faces: [face(0, [wall(tool)]), face(1, [TopoTag(node: tool, item: 0, role: .endCap)])], edges: [edge])
        let moved = topology.qualified(item: 2, qualify)
        #expect(moved.edges == topology.edges)
        #expect(moved.faces.map(\.id) == topology.faces.map(\.id))
        #expect(moved.faces[0].tags == [wall(qualify(tool), item: 2)])
        #expect(moved.faces[1].tags == [TopoTag(node: qualify(tool), item: 2, role: .endCap)])
    }

    @Test func aPickOnAnInstanceThatStillExistsIsNotVanished() {
        let topology = Topology(faces: [face(0, [wall(qualify(tool), item: 0)]), face(1, [wall(qualify(tool), item: 1)])], edges: [])
        #expect(topology.vanishedInstances(in: [wall(qualify(tool), item: 1)]) == [])
    }

    @Test func aPickOnALaterInstanceVanishesWhenTheCountDrops() {
        let topology = Topology(faces: [face(0, [wall(qualify(tool), item: 0)]), face(1, [wall(qualify(tool), item: 1)])], edges: [])
        let pick: Set = [wall(qualify(tool), item: 5), wall(NodeID(), item: 0)]
        #expect(topology.vanishedInstances(in: pick) == [5])
    }

    @Test func aPickOnAnOrdinaryBroadcastItemIsNeverCalledVanished() {
        let topology = Topology(faces: [face(0, [wall(tool, item: 0)])], edges: [])
        #expect(topology.vanishedInstances(in: [wall(tool, item: 9)]) == [])
    }

    @Test func aBlendFaceNamesTheInstancesOfItsSourceEdge() {
        let key = EdgeKey([wall(qualify(tool), item: 4)], [TopoTag(node: NodeID(), item: 0, role: .endCap)])
        let blend = TopoTag(node: NodeID(), item: 0, role: .blend(sourceEdge: key))
        let topology = Topology(faces: [face(0, [wall(qualify(tool), item: 0)])], edges: [])
        #expect(topology.vanishedInstances(in: [blend]) == [4])
    }

    @Test func vanishedInstancesAreSortedWithoutRepeats() {
        let topology = Topology(faces: [face(0, [wall(qualify(tool), item: 0)])], edges: [])
        let pick: Set = [wall(qualify(tool), item: 7), TopoTag(node: qualify(tool), item: 7, role: .endCap),
                         wall(qualify(tool), item: 3),
        ]
        #expect(topology.vanishedInstances(in: pick) == [3, 7])
    }

    @Test func pathsReadLikeTheSpec() {
        #expect(InstancePath.text(3) == "{3}")
        #expect(InstancePath.text(0) == "{0}")
    }
}
