import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// `EdgeContinuity` grading and `Kernel.continuity` on the Fake.
struct EdgeContinuityTests {
    typealias Gap = EdgeContinuity

    @Test func gradeRules() {
        let p = Gap.positionTolerance, a = Gap.angleTolerance, c = Gap.curvatureTolerance, floor = Gap.curvatureFloor
        func grade(_ position: Double, _ angle: Double, _ relative: Double, _ absolute: Double) -> ContinuityClass {
            Gap.grade(positionGap: position, angleGap: angle, curvatureGap: relative, absoluteCurvatureGap: absolute)
        }
        #expect(grade(0, 0, 0, 0) == .g2)
        #expect(grade(p, a, c, 1) == .g2)
        #expect(grade(p * 1.01, 0, 0, 0) == .g0)
        #expect(grade(0, a * 1.01, 0, 0) == .g0)
        #expect(grade(0, a, c * 1.01, 1) == .g1)
        #expect(grade(0, 0, 1, floor) == .g2)
        #expect(grade(0, 0, 1, floor * 1.01) == .g1)
        #expect(ContinuityClass.g0 < .g1 && .g1 < .g2)
    }

    @Test func aBoxEdgeIsG0() async throws {
        let kernel = FakeKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided, tag: tag)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && $0.faces.contains(FaceID(0)) })
        let found = try await kernel.continuity(along: edge.id, of: solid)
        #expect(abs(found.angleGap - .pi / 2) < 1e-9)
        #expect(found.grade == .g0)
        #expect(found.positionGap == 0)
    }

    @Test func aMissingEdgeIsInvalid() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        await #expect(throws: KernelError.self) { try await kernel.continuity(along: EdgeID(999), of: solid) }
    }
}
