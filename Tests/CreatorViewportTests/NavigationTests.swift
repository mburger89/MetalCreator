import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

struct NavigationTests {
    let size = ViewportSize(width: 400, height: 300)

    @Test func orbitTurnsWithThePointer() {
        let pose = CameraPose(target: .zero, distance: 100, yaw: 0, pitch: 0)
        let turned = CameraNavigation.orbit(pose, dx: 50, dy: 25, pivot: nil)
        #expect(isClose(turned.yaw, -50 * ViewportInputMap.orbitRadiansPerPoint))
        #expect(isClose(turned.pitch, 25 * ViewportInputMap.orbitRadiansPerPoint))
        #expect(turned.target == pose.target)
        #expect(turned.distance == pose.distance)
    }

    @Test func orbitClampsPitchAtThePoles() {
        let pose = CameraPose(target: .zero, distance: 100, yaw: 0.3, pitch: 1.4)
        let over = CameraNavigation.orbit(pose, dx: 0, dy: 10_000, pivot: Vector3(5, 5, 5))
        #expect(over.pitch == .pi / 2)
        #expect(over.isFinite)
        let under = CameraNavigation.orbit(pose, dx: 0, dy: -10_000, pivot: nil)
        #expect(under.pitch == -.pi / 2)
        #expect(under.up.isFinite && abs(under.up.length - 1) < 1e-12)
    }

    @Test func orbitKeepsThePivotWhereItWasOnScreen() throws {
        let pose = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let pivot = Vector3(12, -5, 8)
        let before = try #require(CameraMath.project(pivot, pose, size: size)).point
        let after = CameraNavigation.orbit(pose, dx: 40, dy: -25, pivot: pivot)
        let moved = try #require(CameraMath.project(pivot, after, size: size)).point
        #expect(isClose(moved, before, tolerance: 1e-9))
        #expect(!isClose(after.yaw, pose.yaw))
        #expect(isClose(after.distance, pose.distance))
    }

    @Test func yawStaysWithinOneTurn() {
        var pose = CameraPose(target: .zero, distance: 10, yaw: 3, pitch: 0)
        for _ in 0..<100 { pose = CameraNavigation.orbit(pose, dx: -400, dy: 0, pivot: nil) }
        #expect(abs(pose.yaw) <= .pi + 1e-9)
    }

    @Test func panMovesTheSceneWithThePointer() throws {
        let pose = CameraPose(target: Vector3(3, 4, 5), distance: 120, yaw: 0.7, pitch: 0.2, projection: .perspective)
        let after = CameraNavigation.pan(pose, dx: 30, dy: -12, size: size)
        let moved = try #require(CameraMath.project(pose.target, after, size: size)).point
        #expect(isClose(moved, ScreenPoint(size.center.x + 30, size.center.y - 12)))
    }

    @Test func panOrZoomTowardAPointWithoutASizeChangesNoTarget() {
        let pose = CameraPose(target: Vector3(3, 4, 5), distance: 120)
        let empty = ViewportSize(width: 0, height: 0)
        #expect(CameraNavigation.pan(pose, dx: 30, dy: 30, size: empty) == pose)
        let zoomed = CameraNavigation.zoom(pose, factor: 2, toward: ScreenPoint(10, 10), size: empty)
        #expect(zoomed.target == pose.target)
        #expect(isClose(zoomed.distance, 60))
    }

    @Test(arguments: [Projection.perspective, .orthographic])
    func zoomKeepsThePointUnderTheCursor(_ projection: Projection) throws {
        let pose = CameraPose(target: .zero, distance: 100, yaw: -0.4, pitch: 0.5, projection: projection)
        let cursor = ScreenPoint(310, 70)
        let ray = CameraMath.ray(through: cursor, pose, size: size)
        let t = (pose.target - ray.origin).dot(pose.toEye) / ray.direction.dot(pose.toEye)
        let underCursor = ray.point(at: t)
        let after = CameraNavigation.zoom(pose, factor: 1.6, toward: cursor, size: size)
        #expect(isClose(after.distance, 100 / 1.6))
        #expect(isClose(try #require(CameraMath.project(underCursor, after, size: size)).point, cursor, tolerance: 1e-9))
    }

    @Test func zoomIsClampedAndIgnoresNonsense() {
        let pose = CameraPose(target: .zero, distance: 100)
        #expect(CameraNavigation.zoom(pose, factor: 1e12, toward: nil, size: size).distance == CameraNavigation.minimumDistance)
        #expect(CameraNavigation.zoom(pose, factor: 1e-12, toward: nil, size: size).distance == CameraNavigation.maximumDistance)
        #expect(CameraNavigation.zoom(pose, factor: 0, toward: nil, size: size) == pose)
        #expect(CameraNavigation.zoom(pose, factor: .nan, toward: nil, size: size) == pose)
    }

    @Test(arguments: [(Projection.perspective, 2.0), (.perspective, 0.5), (.orthographic, 2.0), (.orthographic, 0.5)])
    func framingFitsEveryCorner(_ projection: Projection, _ aspect: Double) throws {
        let size = ViewportSize(width: 300 * aspect, height: 300)
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: Vector3(500, 0, 0), distance: 3, yaw: 0.8, pitch: 0.6, projection: projection)
        let framed = CameraNavigation.frame(bounds, start, size: size)
        #expect(framed.target == bounds.center)
        #expect(framed.yaw == start.yaw && framed.pitch == start.pitch && framed.projection == projection)
        for corner in corners(bounds) {
            let point = try #require(CameraMath.project(corner, framed, size: size, sceneRadius: 40)).point
            #expect(point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height)
        }
    }

    @Test func framingAFlatOrPointBoundsGivesAFiniteCamera() {
        let start = CameraPose(target: .zero, distance: 50)
        let point = BoundingBox(min: Vector3(1, 2, 3), max: Vector3(1, 2, 3))
        let framed = CameraNavigation.frame(point, start, size: size)
        #expect(framed.isFinite)
        #expect(framed.target == Vector3(1, 2, 3))
        let flat = BoundingBox(min: Vector3(-10, -10, 0), max: Vector3(10, 10, 0))
        #expect(CameraNavigation.frame(flat, start, size: ViewportSize(width: 0, height: 0)).isFinite)
    }

    @Test func framingNonFiniteBoundsKeepsThePose() {
        let start = CameraPose(target: Vector3(1, 1, 1), distance: 50)
        let broken = BoundingBox(min: Vector3(.nan, 0, 0), max: Vector3(1, 1, 1))
        #expect(CameraNavigation.frame(broken, start, size: size) == start)
    }

    @Test(arguments: [
        (Vector3(0, -1, 0), 0.0, 0.0), (Vector3(1, 0, 0), Double.pi / 2, 0.0), (Vector3(0, 1, 0), Double.pi, 0.0),
        (Vector3(-1, 0, 0), -Double.pi / 2, 0.0), (Vector3(1, -1, 1), Double.pi / 4, atan(1 / 2.0.squareRoot())),
    ])
    func orientationLooksFromTheDirection(_ direction: Vector3, _ yaw: Double, _ pitch: Double) throws {
        let o = try #require(CameraNavigation.orientation(lookingFrom: direction, fallbackYaw: 9))
        #expect(isClose(o.yaw, yaw) && isClose(o.pitch, pitch))
    }

    @Test func straightUpKeepsTheFallbackYawAndZeroHasNoOrientation() throws {
        let o = try #require(CameraNavigation.orientation(lookingFrom: Vector3(0, 0, 5), fallbackYaw: 0.7))
        #expect(o.yaw == 0.7 && isClose(o.pitch, .pi / 2))
        #expect(CameraNavigation.orientation(lookingFrom: .zero, fallbackYaw: 0) == nil)
    }

    @Test func arrowsWalkToTheAdjacentFaces() {
        let front = CameraPose(target: .zero, distance: 10, yaw: 0, pitch: 0)
        #expect(isClose(CameraNavigation.rotate(front, .left).toEye, Vector3(-1, 0, 0)))
        #expect(isClose(CameraNavigation.rotate(front, .right).toEye, Vector3(1, 0, 0)))
        let top = CameraNavigation.rotate(front, .up)
        #expect(isClose(top.toEye, .unitZ))
        let back = CameraNavigation.rotate(top, .up)
        #expect(isClose(back.toEye, Vector3(0, 1, 0)), "up from TOP carries on over to BACK")
        let bottom = CameraNavigation.rotate(front, .down)
        #expect(isClose(bottom.toEye, Vector3(0, 0, -1)))
        #expect(isClose(CameraNavigation.rotate(bottom, .down).toEye, Vector3(0, 1, 0)))
    }

    @Test func animationEasesBetweenItsEnds() {
        let from = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.1, projection: .perspective)
        let to = CameraPose(target: Vector3(10, 0, 0), distance: 50, yaw: 0, pitch: 0, projection: .orthographic)
        let animation = CameraAnimation(from: from, to: to, start: 10, duration: 0.25)
        #expect(isClose(animation.pose(at: 9).target, from.target))
        #expect(animation.pose(at: 10.25) == to)
        #expect(animation.pose(at: 99) == to)
        let mid = animation.pose(at: 10.125)
        #expect(isClose(mid.target, Vector3(5, 0, 0)))
        #expect(isClose(mid.distance, 75))
        #expect(mid.projection == .orthographic)
    }

    @Test func animationTakesTheShortWayRound() {
        let from = CameraPose(yaw: 170 * .pi / 180)
        let to = CameraPose(yaw: -170 * .pi / 180)
        let mid = CameraAnimation(from: from, to: to, start: 0, duration: 1).pose(at: 0.5)
        #expect(isClose(cos(mid.yaw), -1, tolerance: 1e-9), "halfway between 170° and −170° is 180°, not 0°")
    }
}
