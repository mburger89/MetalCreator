import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// A backend that answers picks as a test tells it to: a hover from the buffer that has landed (nothing while one is pending, like an
/// SDL_GPU readback on its way), a click from the ID pass of its own view (`clickAnswer` while a buffer is pending).
@MainActor
final class FakeBackend: ViewportBackend {
    var drawnFrames = 0
    var onPickReady: (@MainActor () -> Void)?
    var isPending = false
    var answer: PickTarget?
    /// What the click's own ID pass finds while the hover's buffer is pending.
    var clickAnswer: PickTarget?
    /// What a real backend answers for ``ViewportBackend/drawsWidgets``.
    var drawsWidgets = true
    /// Clicks that asked for their own pick.
    private(set) var clickPicks = 0

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? { isPending ? nil : answer }

    func isPickPending(for frame: ViewportFrame) -> Bool { isPending }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        clickPicks += 1
        return isPending ? clickAnswer : answer
    }

    /// The ID buffer lands: pending ends and the model is told.
    func land(_ target: PickTarget?) {
        isPending = false
        answer = target
        onPickReady?()
    }
}

/// The model talks to its renderer through `ViewportBackend`: picks go through it, and a pick that is still on its way neither
/// clears the hover nor turns a click into one on empty space (the SDL_GPU backend's readback is asynchronous).
@MainActor
struct ViewportBackendTests {
    let face = PickTarget.face(solid: 0, FaceID(2))
    let edge = PickTarget.edge(solid: 0, EdgeID(3))

    func makeModel(_ backend: FakeBackend) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.install(backend)
        return model
    }

    @Test func aModelWithoutABackendHasDrawnNothingAndNoFailure() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        #expect(model.drawnFrames == 0)
        #expect(model.gpuFailureMessage == nil)
    }

    @Test func drawnFramesAreTheBackendsOwn() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.drawnFrames = 3
        #expect(model.drawnFrames == 3)
    }

    @Test func aHoverIsPickedThroughTheBackend() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        model.pointerHovered(at: ScreenPoint(200, 200))
        #expect(model.hovered == face)
        backend.answer = nil
        model.pointerHovered(at: ScreenPoint(10, 10))
        #expect(model.hovered == nil)
    }

    @Test func aHoverKeepsItsFaceWhileThePickIsPendingAndTakesTheLandedOne() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        model.pointerHovered(at: ScreenPoint(200, 200))
        backend.isPending = true
        model.pointerHovered(at: ScreenPoint(210, 200))
        #expect(model.hovered == face, "no answer yet: the face stays, not empty space")
        backend.land(edge)
        #expect(model.hovered == edge, "the landed buffer looks under the pointer again")
    }

    @Test func aClickIsDeliveredAtOnceWhenNothingIsPending() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        var clicked: PickTarget??
        model.events.clicked = { clicked = $0 }
        model.click(at: ScreenPoint(200, 200))
        #expect(clicked == .some(face))
    }

    /// A click is exact while the hover's buffer is on its way (user decision U4, hybrid): the backend renders the click's own ID pass and
    /// waits, so the click is delivered before `click` returns, on its own view's target and to the tool of the press.
    @Test func aClickIsAnsweredAtOnceFromItsOwnIDPassWhileTheHoverBufferIsPending() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        let tool = RecordingTool()
        tool.claims = false
        model.tool = tool
        backend.answer = edge          // the older buffer's answer, which a click must not take
        backend.isPending = true
        backend.clickAnswer = face     // what the click's own pass finds
        var clicked: PickTarget??
        model.events.clicked = { clicked = $0 }
        model.click(at: ScreenPoint(200, 200))
        #expect(clicked == .some(face), "delivered before click returned, from the click's own view")
        #expect(tool.modelPicks == [face], "offered to the tool of the press")
        #expect(backend.clickPicks == 1)
    }

    @Test func aBackendThatDrawsNoCubeLeavesItsCornerToTheScene() {
        let backend = FakeBackend()
        backend.drawsWidgets = false
        let model = makeModel(backend)
        backend.answer = face
        let corner = model.cubeLayout.center
        model.pointerHovered(at: corner)
        #expect(model.hoveredCubeRegion == nil, "no cube is drawn there to highlight")
        #expect(model.hovered == face, "the scene under the corner is picked instead")
        var clicked: PickTarget??
        model.events.clicked = { clicked = $0 }
        model.click(at: corner)
        #expect(clicked == .some(face))
        #expect(!model.isAnimating, "a click there does not turn the camera")
        #expect(model.showsViewCube, "the cube's controls (arrows, View menu) stay")
    }

    @Test func aBackendThatDrawsTheCubeLetsItTurnTheCamera() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        model.pointerHovered(at: model.cubeLayout.center)
        #expect(model.hoveredCubeRegion != nil)
        #expect(model.hovered == nil)
        model.click(at: model.cubeLayout.center)
        #expect(model.isAnimating)
    }
}
