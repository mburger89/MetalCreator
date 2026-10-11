import Foundation
import Testing
@testable import CreatorGeometry

struct PlanePlacementTests {
    /// Planes that face every which way, with the in-plane x axes people get from Plane from Face and by hand.
    static let planes: [Plane] = [
        .xy,
        .xz,
        .yz,
        Plane(origin: Vector3(5, -3, 2), normal: -.unitZ, xAxis: .unitX),
        Plane(origin: Vector3(1, 2, 3), normal: -.unitZ, xAxis: .unitY),
        Plane(origin: .zero, normal: .unitX, xAxis: .unitZ),
        Plane(origin: Vector3(0, 0, 9), normal: -.unitX, xAxis: .unitY),
        Plane(origin: Vector3(-4, 4, 4), normal: Vector3(1, 1, 1).normalized ?? .unitZ, xAxis: Vector3(1, -1, 0).normalized ?? .unitX),
        Plane(origin: .zero, normal: Vector3(-0.3, 0.8, -0.5).normalized ?? .unitZ, xAxis: Vector3(0.8, 0.3, 0).normalized ?? .unitX),
    ]

    @Test(arguments: planes)
    func theWorldFrameLandsOnThePlane(_ plane: Plane) throws {
        let move = try #require(plane.placement)
        #expect(isClose(move.applied(to: .zero), plane.origin))
        #expect(isClose(move.applied(to: .unitX) - plane.origin, plane.xAxis))
        #expect(isClose(move.applied(to: .unitY) - plane.origin, plane.yAxis))
        #expect(isClose(move.applied(to: .unitZ) - plane.origin, plane.normal))
    }

    @Test func aPlaneThatAlreadyFacesUpIsOnlyMoved() throws {
        let move = try #require(Plane(origin: Vector3(1, 2, 3), normal: .unitZ, xAxis: .unitX).placement)
        #expect(move.rotationAxis == nil)
        #expect(move.translation == Vector3(1, 2, 3))
    }

    @Test func anXAxisThatIsNotPerpendicularIsProjected() throws {
        let plane = Plane(origin: .zero, normal: .unitZ, xAxis: Vector3(1, 0, 0.5))
        let move = try #require(plane.placement)
        #expect(isClose(move.applied(to: .unitX), .unitX))
        #expect(isClose(move.applied(to: .unitZ), .unitZ))
    }

    @Test func aScaledNormalOrAxisChangesNothing() throws {
        let plane = Plane(origin: .zero, normal: Vector3(0, 0, -7), xAxis: Vector3(0, 3, 0))
        let move = try #require(plane.placement)
        #expect(isClose(move.applied(to: .unitZ), -.unitZ))
        #expect(isClose(move.applied(to: .unitX), .unitY))
    }

    @Test(arguments: [
        Plane(origin: .zero, normal: .zero, xAxis: .unitX),
        Plane(origin: .zero, normal: .unitZ, xAxis: .zero),
        Plane(origin: .zero, normal: .unitZ, xAxis: Vector3(0, 0, 2)),
        Plane(origin: Vector3(.nan, 0, 0), normal: .unitZ, xAxis: .unitX),
        Plane(origin: .zero, normal: Vector3(0, .infinity, 0), xAxis: .unitX),
    ])
    func aPlaneWithNoUsableDirectionHasNoPlacement(_ plane: Plane) {
        #expect(plane.placement == nil)
    }

    @Test func rotatingAboutZByQuarterTurnsMovesXToY() {
        #expect(isClose(Vector3.unitX.rotated(about: .unitZ, by: .degrees(90)), .unitY))
        #expect(isClose(Vector3.unitX.rotated(about: Vector3(0, 0, 4), by: .degrees(180)), -.unitX))
        #expect(isClose(Vector3.unitX.rotated(about: .zero, by: .degrees(90)), .unitX))
    }

    @Test func aTransformTurnsAboutItsAxisThenMoves() {
        let move = Transform(translation: Vector3(0, 0, 5), rotationAxis: Axis(origin: Vector3(10, 0, 0), direction: .unitZ),
                             rotation: .degrees(90))
        // (11, 0, 0) is 1 mm from the axis along +X; a quarter turn puts it 1 mm along +Y from the axis.
        #expect(isClose(move.applied(to: Vector3(11, 0, 0)), Vector3(10, 1, 5)))
        #expect(isClose(Transform.identity.applied(to: Vector3(1, 2, 3)), Vector3(1, 2, 3)))
    }
}
