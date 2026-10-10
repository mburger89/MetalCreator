import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The plane a flat face gets, shared by the Plane from Face node and the editor that opens before the node has run.
struct FacePlaneTests {
    func face(_ kind: SurfaceKind, normal: Vector3?, centroid: Vector3 = Vector3(1, 2, 3)) -> FaceInfo {
        FaceInfo(id: FaceID(0), kind: kind, normal: normal, area: 1, centroid: centroid, tags: [])
    }

    @Test func aFlatFaceWithANormalGetsThePlaneOnItsCentroid() {
        let plane = PlaneFromFaceNode.plane(of: face(.plane, normal: Vector3(0, 0, 2)))
        #expect(plane == FacePlane.plane(origin: Vector3(1, 2, 3), normal: .unitZ))
        #expect(plane?.normal == .unitZ && plane?.origin == Vector3(1, 2, 3))
    }

    @Test func aCurvedFaceOrOneWithNoNormalGetsNone() {
        #expect(PlaneFromFaceNode.plane(of: face(.cylinder, normal: .unitZ)) == nil)
        #expect(PlaneFromFaceNode.plane(of: face(.plane, normal: nil)) == nil)
        #expect(PlaneFromFaceNode.plane(of: face(.plane, normal: .zero)) == nil)
    }
}
