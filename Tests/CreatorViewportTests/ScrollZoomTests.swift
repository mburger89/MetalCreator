import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// Two-finger scroll and the wheel zoom toward the cursor (spec §6.3, docs/metalui-gaps.md C7 item 1): a run of wheel
/// steps settles the camera once the wheel stops, a trackpad scroll settles it once at its end, and momentum is
/// ignored.
@MainActor
struct ScrollZoomTests {
    let size = ViewportSize(width: 400, height: 300)
    let start = CameraPose(target: .zero, distance: 100, yaw: 0.4, pitch: 0.3)
    let cursor = ScreenPoint(320, 80)

    func makeModel() -> (ViewportModel, () -> [CameraPose]) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: ManualClock())
        model.viewSize = size
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        return (model, { settled })
    }

    /// The model point under `cursor`, on the plane through the target.
    func pointUnderTheCursor(_ pose: CameraPose) -> Vector3 {
        let ray = CameraMath.ray(through: cursor, pose, size: size)
        return ray.point(at: (pose.target - ray.origin).dot(pose.toEye) / ray.direction.dot(pose.toEye))
    }

    @Test func aWheelStepZoomsTowardTheCursorAndSettlesWhenTheWheelStops() async throws {
        let (model, settled) = makeModel()
        let under = pointUnderTheCursor(start)
        #expect(model.scrolled(by: 10, at: cursor, phase: .step), "the viewport claims the scroll")
        #expect(isClose(model.pose.distance, 100 / exp(0.1)))
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, cursor, tolerance: 1e-9))
        #expect(settled().isEmpty, "the wheel may still be turning")
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        model.scrolled(by: -10, at: cursor, phase: .step)
        await model.waitForScroll()
        #expect(isClose(model.pose.distance, 100), "scrolling the other way zooms back out")
        #expect(settled().count == 2)
    }

    /// A free-spinning wheel sends tens of steps a second (and SDL reports every scroll as a step, MetalUI `CI-I`):
    /// they settle the camera, a document write, and re-pick the hover once, not per step (spec §7.3).
    @Test func aRunOfWheelStepsSettlesOnce() async {
        let (model, settled) = makeModel()
        var picks = 0
        model.pick = { _ in
            picks += 1
            return nil
        }
        model.pointerHovered(at: cursor)
        picks = 0
        for _ in 0..<20 { model.scrolled(by: 10, at: cursor, phase: .step) }
        #expect(isClose(model.pose.distance, 100 / exp(2)))
        #expect(settled().isEmpty)
        #expect(picks == 0)
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        #expect(picks == 1)
    }

    @Test func aTrackpadScrollZoomsAndSettlesOnceWhenItEnds() throws {
        let (model, settled) = makeModel()
        let under = pointUnderTheCursor(start)
        for _ in 0..<3 { model.scrolled(by: 20, at: cursor, phase: .moving) }
        #expect(isClose(model.pose.distance, 100 / exp(0.6)))
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, cursor, tolerance: 1e-9))
        #expect(settled().isEmpty, "nothing is reported while the scroll zooms")
        model.scrolled(by: 0, at: cursor, phase: .ended)
        #expect(settled() == [model.pose])
    }

    @Test func momentumIsIgnored() {
        let (model, settled) = makeModel()
        model.scrolled(by: 20, at: cursor, phase: .moving)
        model.scrolled(by: 0, at: cursor, phase: .ended)
        let zoomed = model.pose
        #expect(model.scrolled(by: 30, at: cursor, phase: .momentum), "momentum is still claimed")
        model.scrolled(by: 10, at: cursor, phase: .momentum)
        #expect(model.pose == zoomed)
        #expect(settled() == [zoomed])
    }

    @Test func aScrollThatDoesntZoomReportsNothing() {
        let (model, settled) = makeModel()
        model.scrolled(by: 0, at: cursor, phase: .ended)
        model.scrolled(by: 0, at: cursor, phase: .moving)
        model.scrolled(by: 0, at: cursor, phase: .ended)
        model.scrolled(by: .nan, at: cursor, phase: .step)
        model.scrolled(by: .infinity, at: cursor, phase: .moving)
        model.scrolled(by: 0, at: cursor, phase: .ended)
        #expect(model.pose == start)
        #expect(settled().isEmpty)
    }

    @Test func aScrollStopsACameraAnimation() {
        let (model, _) = makeModel()
        model.perform(.rotate(.up))
        #expect(model.isAnimating)
        model.scrolled(by: 20, at: cursor, phase: .moving)
        #expect(!model.isAnimating)
    }
}
