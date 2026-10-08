import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The events M6's app shell needs: the camera reported when it comes to rest (never per frame), the home
/// view when it's set, and every press (so the shell can release text focus).
@MainActor
struct ViewportEventTests {
    let size = ViewportSize(width: 400, height: 300)

    /// A model with a recorded size whose settled poses, home poses and presses are collected.
    final class Recorder {
        var settled: [CameraPose] = []
        var homes: [CameraPose?] = []
        var presses = 0
    }

    func makeModel(pose: CameraPose? = CameraPose(target: .zero, distance: 100, yaw: 0.3, pitch: 0.2))
        -> (ViewportModel, Recorder) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        let recorder = Recorder()
        model.events.cameraSettled = { recorder.settled.append($0) }
        model.events.homeChanged = { recorder.homes.append($0) }
        model.events.pressed = { recorder.presses += 1 }
        return (model, recorder)
    }

    @Test func aDragReportsTheCameraOnceWhenItIsReleased() {
        let (model, recorder) = makeModel()
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: [])
        for x in stride(from: 210.0, through: 260, by: 10) { model.pointerDragged(to: ScreenPoint(x, 150)) }
        #expect(recorder.settled.isEmpty, "nothing is reported while the drag moves the camera")
        model.pointerUp(at: ScreenPoint(260, 150))
        #expect(recorder.settled == [model.pose])
        #expect(recorder.presses == 1)
    }

    @Test func aClickThatLeavesTheCameraAloneReportsNoPose() {
        let (model, recorder) = makeModel()
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: [])
        model.pointerDragged(to: ScreenPoint(201, 150))
        model.pointerUp(at: ScreenPoint(201, 150))
        #expect(recorder.settled.isEmpty)
        #expect(recorder.presses == 1)
    }

    @Test func anAnimationReportsItsDestinationWhenItEnds() async {
        let (model, recorder) = makeModel()
        model.perform(.view(.front))
        #expect(recorder.settled.isEmpty, "not while it runs")
        await model.waitForAnimation()
        #expect(recorder.settled == [model.pose])
        #expect(model.pose.projection == .orthographic)
    }

    @Test func aStoppedAnimationReportsWhereItStopped() {
        let (model, recorder) = makeModel()
        model.perform(.rotate(.up))
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: [])
        #expect(recorder.settled == [model.pose], "the press froze it where it was on screen")
    }

    @Test func keyZoomAndProjectionReportTheCamera() {
        let (model, recorder) = makeModel()
        model.performKey(.zoomIn)
        #expect(recorder.settled == [model.pose])
        model.perform(.projection(.orthographic))
        #expect(recorder.settled.count == 2)
        #expect(recorder.settled.last?.projection == .orthographic)
    }

    @Test func settingTheHomeViewReportsIt() {
        let (model, recorder) = makeModel()
        model.perform(.setHome)
        #expect(recorder.homes == [model.pose])
        #expect(recorder.settled.isEmpty, "setting home doesn't move the camera")
    }

    @Test func theFirstFramingReportsTheFramedCamera() async throws {
        let (model, recorder) = makeModel(pose: nil)
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        #expect(recorder.settled == [model.pose])
    }

    @Test func theOverlaysMoveIntoTheModelArea() {
        let (model, _) = makeModel()
        model.setModelArea(ViewportInsets(top: 60, leading: 400, bottom: 0, trailing: 300))
        #expect(model.cubeLayout.origin == ScreenPoint(416, 76))
        #expect(model.triadLayout.origin(in: size) == ScreenPoint(416, 300 - 16 - 64))
        #expect(model.modelArea.trailing == 300)
        let centre = model.cubeLayout.center
        model.pointerDown(at: centre, modifiers: [])
        model.pointerUp(at: centre)
        #expect(model.isAnimating, "the moved cube is still the one that's clicked")
    }
}
