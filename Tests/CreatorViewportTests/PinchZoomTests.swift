import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// A trackpad pinch zooms about the pinch centre (spec §6.3, docs/metalui-gaps.md C7 item 2). MetalUI's
/// magnification is cumulative from 1, so every step zooms from the camera the pinch began with.
@MainActor
struct PinchZoomTests {
    let size = ViewportSize(width: 400, height: 300)
    let start = CameraPose(target: .zero, distance: 100, yaw: 0.4, pitch: 0.3)
    let centre = ScreenPoint(120, 220)

    func makeModel() -> (ViewportModel, () -> [CameraPose]) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: ManualClock())
        model.viewSize = size
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        return (model, { settled })
    }

    @Test func aPinchZoomsAboutItsCentreFromTheCameraItBeganWith() throws {
        let (model, settled) = makeModel()
        let ray = CameraMath.ray(through: centre, start, size: size)
        let under = ray.point(at: (start.target - ray.origin).dot(start.toEye) / ray.direction.dot(start.toEye))
        model.pinchChanged(magnification: 1.5, centre: centre)
        model.pinchChanged(magnification: 2, centre: centre)
        #expect(isClose(model.pose.distance, 50), "cumulative: 2×, not 1.5 × 2")
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, centre, tolerance: 1e-9))
        #expect(settled().isEmpty, "nothing is reported while the pinch zooms")
        model.pinchChanged(magnification: 0.5, centre: centre)
        #expect(isClose(model.pose.distance, 200), "pinching back out goes past where it began")
        model.pinchEnded()
        #expect(settled() == [model.pose])
        model.pinchEnded()
        #expect(settled().count == 1, "one end, one report")
    }

    @Test func aSecondPinchStartsFromWhereTheFirstLeftTheCamera() {
        let (model, _) = makeModel()
        model.pinchChanged(magnification: 2, centre: centre)
        model.pinchEnded()
        model.pinchChanged(magnification: 2, centre: centre)
        #expect(isClose(model.pose.distance, 25))
    }

    /// MetalUI drops a pinch whose end was lost without a word (window resigned mid-gesture, its `CI-AB`); the next
    /// pinch must zoom from where the camera is, not from where the lost one began.
    @Test func aPinchThatLostItsEndDoesntPullTheNextOneBack() {
        let (model, settled) = makeModel()
        model.pinchChanged(magnification: 2, centre: centre)
        let lost = model.pose
        model.pinchChanged(magnification: 1.25, centre: ScreenPoint(300, 100))
        #expect(isClose(model.pose.distance, 40), "1.25× from the lost pinch's 50 mm")
        #expect(settled() == [lost], "the lost pinch settled where it was")
    }

    @Test func aHardPinchInHoldsInsteadOfSpringingBack() {
        let (model, _) = makeModel()
        model.pinchChanged(magnification: 0.2, centre: centre)
        model.pinchChanged(magnification: -0.3, centre: centre)
        #expect(isClose(model.pose.distance, 100 / ViewportInputMap.minimumMagnification))
        let held = model.pose
        model.pinchChanged(magnification: .nan, centre: centre)
        #expect(model.pose == held)
        #expect(model.pose.isFinite)
    }

    @Test func aPinchStopsACameraAnimation() {
        let (model, _) = makeModel()
        model.perform(.rotate(.left))
        model.pinchChanged(magnification: 1.2, centre: centre)
        #expect(!model.isAnimating)
    }
}
