import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// `Kernel.shortestDistance` on the Fake: points and straight edges are exact, the rest is refused.
struct FakeKernelMeasureTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func box(_ kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
    }

    @Test func pointToPoint() async throws {
        let found = try await FakeKernel().shortestDistance(between: .point(Vector3(0, 0, 0)), and: .point(Vector3(3, 4, 0)))
        #expect(found == ShapeDistance(distance: 5, from: Vector3(0, 0, 0), to: Vector3(3, 4, 0)))
    }

    @Test func pointToALineEdgeClampsToItsEnds() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        // Edge 0 runs (-5, -10, 0) to (5, -10, 0).
        let beside = try await kernel.shortestDistance(between: .point(Vector3(2, -13, 0)), and: .edge(solid, EdgeID(0)))
        #expect(abs(beside.distance - 3) < 1e-12 && beside.to == Vector3(2, -10, 0))
        let past = try await kernel.shortestDistance(between: .edge(solid, EdgeID(0)), and: .point(Vector3(8, -14, 0)))
        #expect(abs(past.distance - 5) < 1e-12 && past.from == Vector3(5, -10, 0))
    }

    @Test func lineEdgeToLineEdge() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        // Edge 1 is the same segment on the end cap, 5 mm up.
        let found = try await kernel.shortestDistance(between: .edge(solid, EdgeID(0)), and: .edge(solid, EdgeID(1)))
        #expect(abs(found.distance - 5) < 1e-12)
        // Edge 8 rises from (5, -10, 0): it meets edge 0 at its end.
        let touching = try await kernel.shortestDistance(between: .edge(solid, EdgeID(0)), and: .edge(solid, EdgeID(8)))
        #expect(abs(touching.distance) < 1e-12)
    }

    @Test func facesAreRefusedAndMissingIDsAreInvalid() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        await #expect(throws: KernelError.unsupported("measuring a face")) {
            try await kernel.shortestDistance(between: .face(solid, FaceID(0)), and: .point(.zero))
        }
        await #expect(throws: KernelError.invalidInput("That face or edge no longer exists.")) {
            try await kernel.shortestDistance(between: .edge(solid, EdgeID(999)), and: .point(.zero))
        }
    }
}
