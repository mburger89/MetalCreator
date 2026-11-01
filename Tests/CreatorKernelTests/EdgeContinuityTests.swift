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

    @Test func theGradeIsASampleWisePass() {
        // The shim reports the relative gap over samples above the floor only, so a large relative gap with an absolute gap under
        // the floor (flat on both sides) and a small relative gap with a large absolute one both pass; both large do not.
        #expect(Gap.grade(positionGap: 0, angleGap: 0, curvatureGap: 0, absoluteCurvatureGap: 1) == .g2)
        #expect(Gap.grade(positionGap: 0, angleGap: 0, curvatureGap: 0.5, absoluteCurvatureGap: 5e-5) == .g2)
        #expect(Gap.grade(positionGap: 0, angleGap: 0, curvatureGap: 0.5, absoluteCurvatureGap: 1) == .g1)
    }

    @Test func aSeamAndAOneFaceEdgeAreUnsupported() async throws {
        let kernel = FakeKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let cylinder = try await kernel.extrude(.circle(radius: 5, center: Vector2(0, 0), plane: .xy), distance: 10,
                                                mode: .oneSided, tag: tag)
        let seam = try #require(cylinder.topology.edges.first { $0.isSeam })
        await #expect(throws: KernelError.unsupported("continuity of a seam")) { try await kernel.continuity(along: seam.id, of: cylinder) }
        var topology = cylinder.topology
        let edge = try #require(topology.edges.first { !$0.isSeam })
        topology.edges[edge.id.rawValue].faces = [edge.faces[0]]
        let broken = Solid(topology: topology, bounds: cylinder.bounds, storage: FakeStorage())
        await #expect(throws: KernelError.unsupported("continuity of a seam")) { try await kernel.continuity(along: edge.id, of: broken) }
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
