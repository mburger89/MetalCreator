import CreatorGeometry
import Foundation
import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

/// A solid whose every edge is filleted at G2 must report bounds that fit the part.
struct FilletBoundsTests {
    func fitCheck(_ solid: Solid, within limit: Vector3, label: String) {
        let low = solid.bounds.min, high = solid.bounds.max
        print("BOUNDS \(label): \(low) .. \(high)")
        #expect(low.x >= -limit.x - 0.01 && high.x <= limit.x + 0.01)
        #expect(low.y >= -limit.y - 0.01 && high.y <= limit.y + 0.01)
        #expect(low.z >= -0.01 && high.z <= limit.z + 0.01)
    }

    @Test func boxFilletedEverywhereAtG2HasTightBounds() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let result = try await kernel.fillet(solid, edges: solid.topology.edges.map(\.id), radius: 3,
                                             profile: .curvatureContinuous(weight: 1), tag: newTag())
        fitCheck(result.solid, within: Vector3(10, 10, 10), label: "box")
    }

    @Test func trianglePrismFilletedEverywhereAtG2HasTightBounds() async throws {
        let kernel = OCCTKernel()
        let profile = Profile2D.regularPolygon(sides: 3, radius: 15, plane: .xy)
        let solid = try await kernel.extrude(profile, distance: 10, mode: .oneSided, tag: newTag())
        let result = try await kernel.fillet(solid, edges: solid.topology.edges.map(\.id), radius: 1.5,
                                             profile: .curvatureContinuous(weight: 1), tag: newTag())
        fitCheck(result.solid, within: Vector3(15, 15, 10), label: "triangle")
    }
}
