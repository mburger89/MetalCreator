import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// The wheel zooms toward the cursor (spec §6.3) and a two-finger trackpad scroll pans (spec erratum, 2026-10-24): a
/// run of wheel steps settles the camera once the wheel stops; a trackpad gesture settles it once, after its momentum
/// (or after the fingers lift, when none follows).
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
        #expect(model.scrolled(dy: 10, at: cursor, phase: .step), "the viewport claims the scroll")
        #expect(isClose(model.pose.distance, 100 / exp(0.1)))
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, cursor, tolerance: 1e-9))
        #expect(settled().isEmpty, "the wheel may still be turning")
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        model.scrolled(dy: -10, at: cursor, phase: .step)
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
        for _ in 0..<20 { model.scrolled(dy: 10, at: cursor, phase: .step) }
        #expect(isClose(model.pose.distance, 100 / exp(2)))
        #expect(settled().isEmpty)
        #expect(picks == 0)
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        #expect(picks == 1)
    }

    @Test func aPreciseScrollPansAndDoesNotZoom() throws {
        let (model, settled) = makeModel()
        let distance = model.pose.distance
        for _ in 0..<3 { model.scrolled(dx: 20, dy: 10, at: cursor, phase: .moving) }
        #expect(model.pose.distance == distance, "the distance is unchanged")
        #expect(model.pose.target != start.target, "the target moved")
        #expect(settled().isEmpty, "nothing is reported while the scroll pans")
    }

    /// The model follows the fingers: it moves as a drag pan with the same delta does, on both axes.
    @Test func aTrackpadScrollPansLikeADragWithTheSameDelta() {
        let (model, _) = makeModel()
        model.scrolled(dx: 30, dy: -12, at: cursor, phase: .moving)
        let expected = CameraNavigation.pan(start, dx: 30, dy: -12, size: size)
        #expect(model.pose == expected)
        let (dragged, _) = makeModel()
        dragged.dragChanged(from: cursor, to: ScreenPoint(cursor.x + 30, cursor.y - 12), modifiers: [], button: .middle)
        #expect(isClose(model.pose.target, dragged.pose.target))
    }

    @Test func aWheelStepStillZoomsAndDoesNotPan() {
        let (model, _) = makeModel()
        model.scrolled(dx: 7, dy: 10, at: cursor, phase: .step)
        #expect(isClose(model.pose.distance, 100 / exp(0.1)))
        #expect(model.pose.yaw == start.yaw)
    }

    @Test func aPhaselessPreciseStepPansAndSettlesOnceAfterTheDelay() async {
        let (model, settled) = makeModel()
        model.scrolled(dx: 5, dy: 5, at: cursor, phase: .preciseStep)
        #expect(model.pose.distance == start.distance)
        #expect(model.pose.target != start.target)
        await model.waitForScroll()
        #expect(settled() == [model.pose])
    }

    @Test func momentumKeepsPanning() {
        let (model, _) = makeModel()
        model.scrolled(dx: 20, dy: 0, at: cursor, phase: .moving)
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        let panned = model.pose
        #expect(model.scrolled(dx: 30, dy: 10, at: cursor, phase: .momentum), "momentum is still claimed")
        let first = model.pose
        #expect(first.target != panned.target)
        model.scrolled(dx: 10, dy: 5, at: cursor, phase: .momentum)
        #expect(model.pose.target != first.target)
        #expect(model.pose.distance == start.distance)
    }

    @Test func aGestureWithMomentumSettlesOnceWhenTheMomentumEnds() async {
        let (model, settled) = makeModel()
        model.scrolled(dx: 20, dy: 4, at: cursor, phase: .moving)
        model.scrolled(dx: 20, dy: 4, at: cursor, phase: .moving)
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        model.scrolled(dx: 15, dy: 3, at: cursor, phase: .momentum)
        model.scrolled(dx: 5, dy: 1, at: cursor, phase: .momentum)
        #expect(settled().isEmpty, "the glide is still under way")
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .momentumEnded)
        #expect(settled() == [model.pose])
        await model.waitForScroll()
        #expect(settled().count == 1, "one settle for the whole gesture")
    }

    @Test func aGestureWithoutMomentumSettlesOnceAfterTheFingersLift() async {
        let (model, settled) = makeModel()
        model.scrolled(dx: 20, dy: 4, at: cursor, phase: .moving)
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        await model.waitForScroll()
        #expect(settled().count == 1)
    }

    @Test func aCancelledScrollSettlesAtOnce() {
        let (model, settled) = makeModel()
        model.scrolled(dx: 20, dy: 0, at: cursor, phase: .moving)
        model.scrolled(dy: 0, at: cursor, phase: .cancelled)
        #expect(settled() == [model.pose])
    }

    @Test func aPanReStartedDuringTheWaitIsOneGesture() async {
        let (model, settled) = makeModel()
        model.scrolled(dx: 20, dy: 0, at: cursor, phase: .moving)
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        model.scrolled(dx: 20, dy: 0, at: cursor, phase: .moving)
        await model.waitForScroll()
        #expect(settled().isEmpty, "a new scroll cancelled the wait")
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        await model.waitForScroll()
        #expect(settled() == [model.pose])
    }

    @Test func aScrollThatDoesntMoveReportsNothing() async {
        let (model, settled) = makeModel()
        model.scrolled(dy: 0, at: cursor, phase: .ended)
        await model.waitForScroll()
        model.scrolled(dy: 0, at: cursor, phase: .moving)
        model.scrolled(dy: 0, at: cursor, phase: .ended)
        await model.waitForScroll()
        model.scrolled(dy: .nan, at: cursor, phase: .step)
        await model.waitForScroll()
        model.scrolled(dx: .nan, dy: .infinity, at: cursor, phase: .moving)
        model.scrolled(dy: 0, at: cursor, phase: .momentumEnded)
        #expect(model.pose == start)
        #expect(settled().isEmpty)
    }

    @Test func aTrackpadPanStopsACameraAnimation() {
        let (model, _) = makeModel()
        model.perform(.rotate(.up))
        #expect(model.isAnimating)
        model.scrolled(dx: 20, dy: 0, at: cursor, phase: .moving)
        #expect(!model.isAnimating)
    }

    @Test func aWheelStepStopsACameraAnimation() {
        let (model, _) = makeModel()
        model.perform(.rotate(.up))
        model.scrolled(dy: 20, at: cursor, phase: .step)
        #expect(!model.isAnimating)
    }

    /// The wheel's debounce (spec §7.3): each step restarts the wait, so a settle comes `wheelSettleDelay` after the
    /// last step and not before. Needs a clock whose sleeps last (`ManualClock`'s return at once).
    @Test func theWheelSettlesOnlyOnceItHasBeenStillForTheWholeDelay() async {
        let clock = GatedClock()
        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: clock)
        model.viewSize = size
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        let delay = ViewportInputMap.wheelSettleDelay
        model.scrolled(dy: 10, at: cursor, phase: .step)
        await clock.advance(by: delay * 0.6)
        model.scrolled(dy: 10, at: cursor, phase: .step)
        await clock.advance(by: delay * 0.6)
        #expect(settled.isEmpty, "the first step's wait ran out, but the second step restarted it")
        await clock.advance(by: delay * 0.6)
        #expect(settled == [model.pose], "settled once, after the wheel was still for the whole delay")
    }

    /// SDL's synthesized stream (MetalUI XP-G28): precise `.began`/`.changed` events, then one zero-delta `.ended` about
    /// 0.15 s after the last, and never a momentum phase. It pans, and settles once, `wheelSettleDelay` after the end.
    @Test func anSDLTrackpadStreamPansAndSettlesOnceAfterTheEnd() async {
        let clock = GatedClock()
        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: clock)
        model.viewSize = size
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        let delay = ViewportInputMap.wheelSettleDelay
        for _ in 0..<4 { model.scrolled(dx: 6, dy: 3, at: cursor, phase: .moving) }
        #expect(model.pose.distance == start.distance, "a trackpad stream pans and does not zoom")
        #expect(model.pose.target != start.target)
        await clock.advance(by: delay * 2)
        #expect(settled.isEmpty, "no settle while the stream is open")
        model.scrolled(dx: 0, dy: 0, at: cursor, phase: .ended)
        await clock.advance(by: delay * 0.6)
        #expect(settled.isEmpty, "the settle waits out the whole delay after the end")
        await clock.advance(by: delay * 0.6)
        #expect(settled == [model.pose], "settled once")
        await clock.advance(by: delay * 2)
        #expect(settled.count == 1)
    }

    /// F, an arrow or a cube click during a scroll starts an animation; the next scroll event takes over from what
    /// is shown, as a drag does, instead of letting the animation finish over it.
    @Test func aScrollEventStopsAnAnimationStartedMidScroll() {
        let (model, _) = makeModel()
        model.scrolled(dx: 10, dy: 10, at: cursor, phase: .moving)
        model.perform(.view(.top))
        #expect(model.isAnimating)
        model.scrolled(dx: 10, dy: 10, at: cursor, phase: .moving)
        #expect(!model.isAnimating, "the scroll's pose is shown, not the old interpolation")
    }
}
