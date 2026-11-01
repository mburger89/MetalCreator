import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelFaceRadiusTests {
    @Test func aPrismsArcSideHasTheArcsRadiusCentreAndAxis() async throws {
        let profile = Profile2D.circle(radius: 3, center: Vector2(1, 2), plane: .xy)
        let solid = try await FakeKernel().extrude(profile, distance: 5, mode: .oneSided,
                                                   tag: NodeTag(node: NodeID(), item: 0))
        let side = try #require(solid.topology.faces.first { $0.kind == .cylinder })
        #expect(side.radius == 3)
        #expect(side.axisPoint == Plane.xy.point(Vector2(1, 2)))
        #expect(side.normal == Plane.xy.normal)
        for face in solid.topology.faces where face.kind == .plane {
            #expect(face.radius == nil && face.axisPoint == nil)
        }
    }

    @Test func aFilletFaceHasTheFilletRadius() async throws {
        let kernel = FakeKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let box = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let edge = try #require(box.topology.edges.first)
        let rounded = try await kernel.fillet(box, edges: [edge.id], radius: 1.5, tag: tag)
        let face = try #require(rounded.topology.faces.last)
        #expect(face.kind == .cylinder && face.radius == 1.5 && face.axisPoint != nil)
    }
}
