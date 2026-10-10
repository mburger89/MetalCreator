import CreatorGeometry
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// A face pick renamed for a group keeps the position it recorded (roadmap "Naming: face picks on merged faces").
struct FacePickRenamingTests {
    @Test func renamingATagKeepsTheRecordedNormalAndCentroid() {
        let a = NodeID(), b = NodeID()
        let pick = FacePick(tags: [TopoTag(node: a, item: 0, role: .endCap)], normal: .unitZ, centroid: Vector3(1, 2, 3))
        let renamed = ConstantValue.facePick(pick).renamingTags([a: b])
        #expect(renamed == .facePick(FacePick(tags: [TopoTag(node: b, item: 0, role: .endCap)],
                                              normal: .unitZ, centroid: Vector3(1, 2, 3))))
    }
}
