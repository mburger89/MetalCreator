@testable import CreatorGeometry
import Testing
@testable import CreatorKernel

struct FakeKernelSplineTests {
    @Test func aProfileWithASplineIsRefusedInWords() async {
        let curve = SplineDefinition(points: [Vector2(0, 0), Vector2(5, 3), Vector2(10, 0)]).curve()
        let profile = Profile2D(plane: .xy, segments: [.spline(curve), .line(Vector2(10, 0), Vector2(0, 0))])
        let kernel = FakeKernel()
        await #expect(throws: KernelError.splinesUnsupported) {
            try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        }
    }
}
