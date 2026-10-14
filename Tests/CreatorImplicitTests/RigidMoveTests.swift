import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct RigidMoveTests {
    @Test func theMovePutsTheLocalFrameOnThePlane() throws {
        let plane = Plane(origin: Vector3(1, 2, 3), normal: .unitX, xAxis: .unitY)
        let move = try #require(RigidMove(plane: plane))
        #expect((move.toWorld(.zero) - Vector3(1, 2, 3)).length < 1e-12)
        #expect((move.toWorld(.unitZ) - Vector3(2, 2, 3)).length < 1e-12, "local +Z goes along the normal")
        #expect((move.toWorld(.unitX) - Vector3(1, 3, 3)).length < 1e-12, "local +X goes along the plane's x axis")
    }

    @Test func toLocalUndoesToWorld() throws {
        let move = try #require(RigidMove(plane: Plane(origin: Vector3(5, -3, 2), normal: Vector3(1, 1, 1), xAxis: Vector3(1, -1, 0))))
        for point in [Vector3.zero, Vector3(1, 2, 3), Vector3(-7, 4, 0.5)] {
            #expect((move.toLocal(move.toWorld(point)) - point).length < 1e-12)
        }
    }

    @Test func anXAxisOffTheNormalIsMadePerpendicular() throws {
        let move = try #require(RigidMove(plane: Plane(origin: .zero, normal: .unitZ, xAxis: Vector3(1, 0, 0.5))))
        #expect(abs(move.xAxis.dot(move.zAxis)) < 1e-12 && abs(move.xAxis.length - 1) < 1e-12)
    }

    @Test func aPlaneWithoutADirectionHasNoMove() {
        #expect(RigidMove(plane: Plane(origin: .zero, normal: .zero, xAxis: .unitX)) == nil)
        #expect(RigidMove(plane: Plane(origin: .zero, normal: .unitZ, xAxis: .unitZ)) == nil)
        #expect(RigidMove(plane: Plane(origin: Vector3(.nan, 0, 0), normal: .unitZ, xAxis: .unitX)) == nil)
    }

    @Test func theBoundsOfAMovedBoxContainItsCorners() throws {
        let move = try #require(RigidMove(plane: Plane(origin: .zero, normal: .unitZ, xAxis: Vector3(1, 1, 0))))
        let box = BoundingBox(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        let moved = move.bounds(of: box)
        #expect(abs(moved.max.x - 2.0.squareRoot()) < 1e-12 && abs(moved.max.z - 1) < 1e-12)
    }
}
