import CreatorGeometry
import Foundation
import simd
import Testing
@testable import CreatorViewport

struct CameraMathTests {
    let size = ViewportSize(width: 400, height: 300)

    static let poses: [CameraPose] = [
        CameraPose(target: Vector3(1, 2, 3), distance: 50, yaw: 0.3, pitch: 0.4, projection: .perspective),
        CameraPose(target: Vector3(-4, 0, 9), distance: 80, yaw: -2.1, pitch: -0.7, projection: .orthographic),
        CameraPose(target: .zero, distance: 30, yaw: 1, pitch: .pi / 2, projection: .perspective),
        CameraPose(target: .zero, distance: 30, yaw: 0, pitch: -.pi / 2, projection: .orthographic),
    ]

    @Test(arguments: poses)
    func theTargetProjectsToTheCentre(_ pose: CameraPose) throws {
        let projected = try #require(CameraMath.project(pose.target, pose, size: size, sceneRadius: 10))
        #expect(isClose(projected.point, size.center))
        #expect(projected.depth > 0 && projected.depth < 1)
    }

    @Test(arguments: poses)
    func aRayThroughAProjectedPointPassesThroughIt(_ pose: CameraPose) throws {
        let world = pose.target + pose.right * 7 - pose.up * 4 + pose.toEye * 3
        let projected = try #require(CameraMath.project(world, pose, size: size, sceneRadius: 20))
        let ray = CameraMath.ray(through: projected.point, pose, size: size)
        let offset = world - ray.origin
        let along = offset.dot(ray.direction)
        #expect((offset - ray.direction * along).length < 1e-6)
        #expect(abs(ray.direction.length - 1) < 1e-12)
    }

    @Test(arguments: poses)
    func aSceneAroundTheTargetFitsTheDepthRange(_ pose: CameraPose) throws {
        let reach = 25.0 / 3.0.squareRoot()
        let scene = BoundingBox(min: pose.target - Vector3(reach, reach, reach), max: pose.target + Vector3(reach, reach, reach))
        for corner in corners(scene) {
            let projected = try #require(CameraMath.project(corner, pose, size: size, sceneRadius: 25))
            #expect(projected.depth >= 0 && projected.depth <= 1, "corner \(corner) has depth \(projected.depth)")
        }
    }

    @Test func theViewMatrixPutsTheEyeAtTheOriginLookingDownMinusZ() {
        let pose = Self.poses[0]
        let view = CameraMath.view(pose)
        let eye = view * SIMD4(pose.eye.x, pose.eye.y, pose.eye.z, 1)
        #expect(abs(eye.x) < 1e-9 && abs(eye.y) < 1e-9 && abs(eye.z) < 1e-9)
        let target = view * SIMD4(pose.target.x, pose.target.y, pose.target.z, 1)
        #expect(abs(target.x) < 1e-9 && abs(target.y) < 1e-9)
        #expect(isClose(target.z, -pose.distance))
    }

    @Test(arguments: [Projection.perspective, .orthographic])
    func theVisibleHeightSpansTheView(_ projection: Projection) throws {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0, projection: projection)
        let top = try #require(CameraMath.project(pose.up * 20, pose, size: size))
        let bottom = try #require(CameraMath.project(pose.up * -20, pose, size: size))
        #expect(abs(top.point.y) < 1e-9)
        #expect(isClose(bottom.point.y, size.height))
        #expect(isClose(CameraMath.millimetresPerPoint(pose, size: size), 40 / 300))
    }

    @Test func orthographicRaysCountHitsBehindTheEye() {
        let ortho = CameraMath.ray(through: size.center, Self.poses[1], size: size)
        #expect(ortho.minimumT == -.infinity)
        #expect(CameraMath.ray(through: size.center, Self.poses[0], size: size).minimumT == 0)
    }

    @Test func pointsBehindAPerspectiveCameraDoNotProject() {
        let pose = Self.poses[0]
        #expect(CameraMath.project(pose.eye + pose.toEye * 5, pose, size: size) == nil)
    }

    @Test func floatConversionKeepsTheColumns() {
        #expect(Matrix4.identity.float == matrix_identity_float4x4)
        let asymmetric = Matrix4(c0: [1, 2, 3, 4], c1: [5, 6, 7, 8], c2: [9, 10, 11, 12], c3: [13, 14, 15, 16])
        let converted = asymmetric.float
        #expect(converted.columns.0 == SIMD4<Float>(1, 2, 3, 4))
        #expect(converted.columns.1 == SIMD4<Float>(5, 6, 7, 8))
        #expect(converted.columns.3 == SIMD4<Float>(13, 14, 15, 16))
        let product = Matrix4.identity * Matrix4.identity
        #expect(product == .identity)
    }
}
