import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Drain holes (implicit spec §3.6, §4.6, §7): the voids of an implicit are found on its coarse grid and drilled out.
struct DrainHolesTests {
    /// A ball of radius 3 with a sealed cavity of radius 1.5 about the origin.
    let ball = ImplicitSolid.subtract([.sphere(radius: 3), .sphere(radius: 1.5)], blend: .constant(0))

    @Test func theCavityOfABallIsFoundAtItsLowestPoint() async throws {
        let points = try await DrainHoles.drainPoints(of: ball, direction: Vector3(0, 0, -1), using: CPUBatchEvaluator(ball))
        let point = try #require(points.first)
        #expect(points.count == 1)
        #expect(point.z < -1.1 && point.z > -1.6 && abs(point.x) < 0.2 && abs(point.y) < 0.2, "\(point)")
        let sideways = try await DrainHoles.drainPoints(of: ball, direction: .unitX, using: CPUBatchEvaluator(ball))
        #expect(try #require(sideways.first).x > 1.1, "the lowest along +X is the far side")
    }

    @Test func aSolidBallHasNothingToDrainAndTwoCavitiesNeedTwoHoles() async throws {
        let solid = ImplicitSolid.sphere(radius: 3)
        #expect(try await DrainHoles.drainPoints(of: solid, direction: .unitZ, using: CPUBatchEvaluator(solid)).isEmpty)
        let slab = ImplicitSolid.box(halfSize: Vector3(8, 3, 3), cornerRadius: 0)
        func cavity(at x: Double) -> ImplicitSolid {
            .moved(.sphere(radius: 1.2), RigidMove(origin: Vector3(x, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        }
        let (left, right) = (cavity(at: -4), cavity(at: 4))
        let two = ImplicitSolid.subtract([slab, left, right], blend: .constant(0))
        let points = try await DrainHoles.drainPoints(of: two, direction: Vector3(0, 0, -1), using: CPUBatchEvaluator(two))
        #expect(points.count == 2 && points.map(\.x).sorted()[0] < 0 && points.map(\.x).sorted()[1] > 0)
    }

    @Test func aHoleLeavesAnOpenTunnelFromThePointToTheOutside() {
        let drilled = DrainHoles.drilled(ball, at: [Vector3(0, 0, -1.4)], diameter: 1, direction: Vector3(0, 0, -1))
        #expect(ball.signedDistance(at: Vector3(0, 0, -2.5)) < 0 && drilled.signedDistance(at: Vector3(0, 0, -2.5)) > 0)
        #expect(drilled.signedDistance(at: Vector3(0.4, 0, -2.5)) > 0, "inside the hole's radius")
        #expect(drilled.signedDistance(at: Vector3(0.9, 0, -2.5)) < 0, "outside it the wall is still there")
        #expect(drilled.signedDistance(at: Vector3(0, 0, 2.5)) < 0, "nothing is drilled the other way")
        #expect(drilled.signedDistance(at: Vector3(0, 0, -3.5)) > 0)
        #expect(drilled.bounds == ball.bounds)
    }

    @Test func aHoleAlongAnyDirectionPointsThatWay() {
        for direction in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 1).normalized ?? .unitX, Vector3(0, 0.0, 1)] {
            let drilled = DrainHoles.drilled(ball, at: [.zero], diameter: 0.8, direction: direction)
            #expect(drilled.signedDistance(at: direction * 2.2) > 0, "\(direction)")
            #expect(drilled.signedDistance(at: direction * -2.2) < 0, "\(direction)")
        }
    }

    @Test func noPointsOrNoDirectionLeavesTheSolidAlone() {
        #expect(DrainHoles.drilled(ball, at: [], diameter: 1, direction: .unitZ) == ball)
        #expect(DrainHoles.drilled(ball, at: [.zero], diameter: 1, direction: .zero) == ball)
    }

    @Test func aSolidWithNoFiniteBoundsHasNoGrid() async {
        let unbounded = ImplicitSolid.isosurface(.constant(0), level: 0, maxSlope: 1,
                                                 region: BoundingBox(min: Vector3(-.infinity, 0, 0), max: Vector3(1, 1, 1)))
        await #expect(throws: ImplicitMeshingError.empty) {
            try await DrainHoles.drainPoints(of: unbounded, direction: .unitZ, using: CPUBatchEvaluator(unbounded))
        }
    }
}
