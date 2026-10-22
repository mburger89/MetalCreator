import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// A backend that answers picks as a test tells it to, and holds them back like an SDL_GPU readback that has not landed.
@MainActor
final class FakeBackend: ViewportBackend {
    var drawnFrames = 0
    var onPickReady: (@MainActor () -> Void)?
    var isPending = false
    var answer: PickTarget?
    /// What a real backend answers for ``ViewportBackend/drawsWidgets``.
    var drawsWidgets = true
    private var waiters: [CheckedContinuation<PickTarget?, Never>] = []
    private var registration: CheckedContinuation<Void, Never>?

    /// How many clicks are waiting for the ID buffer.
    var waitersRegistered: Int { waiters.count }

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? { isPending ? nil : answer }

    func isPickPending(for frame: ViewportFrame) -> Bool { isPending }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
        if !isPending { return answer }
        return await withCheckedContinuation {
            waiters.append($0)
            registration?.resume()
            registration = nil
        }
    }

    /// Returns once a click is waiting (at once if one already is): the model's click `Task` has run and registered.
    func untilAWaiterIsRegistered() async {
        if !waiters.isEmpty { return }
        await withCheckedContinuation { registration = $0 }
    }

    /// The ID buffer lands: pending ends, waiting clicks are answered and the model is told.
    func land(_ target: PickTarget?) {
        isPending = false
        answer = target
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume(returning: target) }
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

    @Test(.timeLimit(.minutes(1)))
    func aClickWaitsForAPendingPickAndIsThenDeliveredOnTheLandedTarget() async {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.isPending = true
        var landed = false
        var deliveredBeforeLanding = false
        var waitersWhenLanding = 0
        let delivered = await withCheckedContinuation { (continuation: CheckedContinuation<PickTarget?, Never>) in
            model.events.clicked = {
                deliveredBeforeLanding = !landed
                continuation.resume(returning: $0)
            }
            model.click(at: ScreenPoint(200, 200))
            Task {
                await backend.untilAWaiterIsRegistered()
                waitersWhenLanding = backend.waitersRegistered
                landed = true
                backend.land(face)
            }
        }
        #expect(waitersWhenLanding == 1, "the click is waiting for the buffer, not already answered")
        #expect(!deliveredBeforeLanding, "nothing was delivered while the pick was pending")
        #expect(delivered == face, "the click was on the face, not on empty space")
    }

    @Test(.timeLimit(.minutes(1)))
    func aWaitingClickGoesToTheToolItWasMadeWithAndNotTheOneSetWhileItWaited() async {
        let backend = FakeBackend()
        let model = makeModel(backend)
        let first = RecordingTool()
        first.claims = false
        let second = RecordingTool()
        second.claims = false
        model.tool = first
        backend.isPending = true
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<PickTarget?, Never>) in
            model.events.clicked = { continuation.resume(returning: $0) }
            model.click(at: ScreenPoint(200, 200))
            model.tool = second   // the tool changes in the milliseconds before the buffer lands
            Task {
                await backend.untilAWaiterIsRegistered()
                backend.land(face)
            }
        }
        #expect(first.modelPicks == [face], "the press belonged to the first tool")
        #expect(second.modelPicks.isEmpty)
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
