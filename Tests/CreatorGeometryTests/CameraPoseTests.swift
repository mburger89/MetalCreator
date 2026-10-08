import Foundation
import Testing
@testable import CreatorGeometry

struct CameraPoseTests {
    @Test func yawZeroLooksFromTheFront() {
        let pose = CameraPose(target: .zero, distance: 10, yaw: 0, pitch: 0)
        #expect(isClose(pose.toEye, Vector3(0, -1, 0)))
        #expect(isClose(pose.right, .unitX))
        #expect(isClose(pose.up, .unitZ))
        #expect(isClose(pose.eye, Vector3(0, -10, 0)))
    }

    @Test func pitchUpLooksDownWithYUpOnScreen() {
        let pose = CameraPose(target: .zero, distance: 10, yaw: 0, pitch: .pi / 2)
        #expect(isClose(pose.toEye, .unitZ))
        #expect(isClose(pose.right, .unitX))
        #expect(isClose(pose.up, .unitY))
    }

    @Test(arguments: [(0.0, 0.0), (1.2, 0.4), (-2.5, -0.9), (0.7, Double.pi / 2), (3.0, -Double.pi / 2)])
    func basisIsOrthonormalAtThePoles(_ yaw: Double, _ pitch: Double) {
        let pose = CameraPose(target: Vector3(1, 2, 3), distance: 5, yaw: yaw, pitch: pitch)
        for v in [pose.toEye, pose.right, pose.up] {
            #expect(abs(v.length - 1) < 1e-12)
            #expect(v.isFinite)
        }
        #expect(abs(pose.toEye.dot(pose.right)) < 1e-12)
        #expect(abs(pose.toEye.dot(pose.up)) < 1e-12)
        #expect(abs(pose.right.dot(pose.up)) < 1e-12)
        #expect(isClose(pose.right.cross(pose.up), pose.toEye), "the camera frame is right-handed")
    }

    @Test func visibleHeightFollowsTheFieldOfView() {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0)
        #expect(isClose(pose.visibleHeight, 40, tolerance: 1e-9))
    }

    @Test func finitenessCoversEveryField() {
        #expect(CameraPose().isFinite)
        #expect(!CameraPose(target: Vector3(.nan, 0, 0)).isFinite)
        #expect(!CameraPose(distance: 0).isFinite)
        #expect(!CameraPose(distance: .infinity).isFinite)
        #expect(!CameraPose(yaw: .nan).isFinite)
    }

    @Test func roundTripsThroughJSON() throws {
        let pose = CameraPose(target: Vector3(1, -2, 3), distance: 42, yaw: 0.5, pitch: -0.25, projection: .orthographic)
        #expect(try JSONDecoder().decode(CameraPose.self, from: JSONEncoder().encode(pose)) == pose)
    }
}
