import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// A pick on an item that is no instance path (an imported board's hashed feature) that the topology no longer has says so in
/// the board's words, once; a real instance path keeps the pattern wording (KiCad import spec, finding 8).
struct ImportedFeatureVanishedTests {
    let origin = NodeID.instanceScoped([NodeID(), NodeID()])
    let wall = NodeID()
    /// A negative number `InstancePath.item(for:)` never makes (depth 0).
    let hashed = -((1 << 59) + 12345)

    var gone: Topology {
        Topology(faces: [FaceInfo(id: FaceID(0), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero,
                                  tags: [TopoTag(node: wall, item: 0, role: .side(segment: 0))]),
        ], edges: [])
    }

    func tag(_ item: Int) -> TopoTag { TopoTag(node: origin, item: item, role: .side(segment: 0)) }

    @Test func aHashedItemIsNoPath() {
        #expect(InstancePath.indices(ofItem: hashed) == nil)
        #expect(InstancePath.partition([hashed, 3, hashed - 1]) == (paths: [3], hasOther: true))
    }

    @Test func edgePicksSayItOnce() {
        let pick = EdgePick(key: EdgeKey([tag(hashed), tag(hashed - 1)], [TopoTag(node: wall, item: 0, role: .side(segment: 0))]),
                            matchCount: 1)
        let match = EdgeTagMatch.resolve([pick], in: gone)
        #expect(match.warnings == ["The picked feature no longer exists in the imported board."])
    }

    @Test func aRealPathKeepsItsWording() {
        let item = InstancePath.item(for: [0, 2]) ?? 0
        #expect(EdgeTagMatch.vanishedInstances([item]) == "Instance {0;2} no longer exists, so the edge picked on it isn't selected.")
        #expect(EdgeTagMatch.vanishedInstances([item, hashed]) ==
            "Instance {0;2} no longer exists, so the edge picked on it isn't selected. "
            + "The picked feature no longer exists in the imported board.")
    }

    @Test func facePicksSayItToo() {
        #expect(FacePickWording.vanished([hashed, hashed - 1]) == InstancePath.importedFeatureVanished)
        #expect(FacePickWording.vanished([4]) == "Instance {4} no longer exists, so the picked face isn't there any more. "
            + "Pick the face again.")
    }
}
