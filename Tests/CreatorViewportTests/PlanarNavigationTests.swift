import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// A tool that asks for planar navigation (the sketch editor) locks the camera's orientation to the plane it faces:
/// drags pan, scroll and pinch zoom, the view cube is hidden and its commands do nothing, and F frames the tool's
/// bounds without turning. Without such a tool the viewport orbits as before.
@MainActor
struct PlanarNavigationTests {
    func makeModel(tool: RecordingTool?) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, yaw: 0.3,
                                                                             pitch: 0.8, projection: .orthographic),
                                  clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.tool = tool
        return model
    }

    func planarTool(claims: Bool = false) -> RecordingTool {
        let tool = RecordingTool()
        tool.navigation = .planar
        tool.claims = claims
        return tool
    }

    func expectSameOrientation(_ a: CameraPose, _ b: CameraPose, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.yaw == b.yaw && a.pitch == b.pitch && a.projection == b.projection, sourceLocation: sourceLocation)
    }

    @Test func aPrimaryDragTheToolDeclinesPans() {
        let model = makeModel(tool: planarTool())
        let before = model.pose
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 160), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .pan)
        #expect(model.cursor == .grabbing)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(240, 170), modifiers: [], button: .primary)
        expectSameOrientation(model.pose, before)
        #expect(model.pose.target != before.target, "the view followed the pointer")
    }

    @Test func aPrimaryDragTheToolTakesStillGoesToTheTool() {
        let tool = planarTool(claims: true)
        let model = makeModel(tool: tool)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 160), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .tool)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(240, 170), modifiers: [], button: .primary)
        #expect(tool.calls.prefix(3) == ["began 200,150", "dragged 230,160", "ended 240,170"])
    }

    @Test(arguments: [ViewportPointerButton.secondary, .middle])
    func rightAndMiddleDragsPan(_ button: ViewportPointerButton) {
        let model = makeModel(tool: planarTool())
        let before = model.pose
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(260, 120), modifiers: [], button: button)
        #expect(model.activeDragMode == .pan)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(260, 120), modifiers: [], button: button)
        expectSameOrientation(model.pose, before)
        #expect(model.pose.target != before.target)
    }

    @Test func modifiedDragsPanOrZoomAndNeverTurn() {
        let model = makeModel(tool: planarTool())
        let before = model.pose
        for modifiers: ViewportModifiers in [.shift, .option, [.option, .shift], .command, .control] {
            model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(260, 100), modifiers: modifiers, button: .primary)
            #expect(model.activeDragMode != .orbit)
            model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(260, 100), modifiers: modifiers, button: .primary)
        }
        expectSameOrientation(model.pose, before)
    }

    /// The plane through the camera's target, facing it: the zoom keeps the point under the pointer fixed on it.
    func planePoint(_ model: ViewportModel, under point: ScreenPoint, on plane: Plane) -> Vector2? {
        ViewportProjector(pose: model.pose, size: model.viewSize).planePoint(under: point, on: plane)
    }

    @Test func scrollAndPinchStillZoomTowardThePointer() throws {
        let model = makeModel(tool: planarTool())
        let before = model.pose
        let plane = Plane(origin: before.target, normal: before.toEye, xAxis: before.right)
        let scrollAt = ScreenPoint(300, 100)
        let underScroll = try #require(planePoint(model, under: scrollAt, on: plane))
        model.scrolled(by: 20, at: scrollAt, phase: .moving)
        model.scrolled(by: 0, at: scrollAt, phase: .ended)
        #expect(model.pose.distance < before.distance)
        let afterScroll = try #require(planePoint(model, under: scrollAt, on: plane))
        #expect((afterScroll - underScroll).length < 1e-6, "the point under the pointer stays put")
        let pinchAt = ScreenPoint(100, 200)
        let underPinch = try #require(planePoint(model, under: pinchAt, on: plane))
        model.pinchChanged(magnification: 1.5, centre: pinchAt)
        model.pinchEnded()
        let afterPinch = try #require(planePoint(model, under: pinchAt, on: plane))
        #expect((afterPinch - underPinch).length < 1e-6)
        expectSameOrientation(model.pose, before)
    }

    @Test func theCubeIsHiddenAndItsPlaceIsTheTools() {
        let tool = planarTool(claims: true)
        let model = makeModel(tool: tool)
        #expect(!model.showsViewCube)
        #expect(!model.frame(at: 0).showsViewCube, "the renderer doesn't draw it")
        let onCube = model.cubeLayout.center
        model.pointerHovered(at: onCube)
        #expect(model.hoveredCubeRegion == nil)
        model.click(at: onCube)
        #expect(tool.calls.contains("clicked \(Int(onCube.x)),\(Int(onCube.y))"), "a click there draws, as anywhere")
        #expect(!model.isAnimating)
        tool.claims = false
        let before = model.pose
        model.dragChanged(from: onCube, to: ScreenPoint(onCube.x + 40, onCube.y), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .pan, "a drag there pans, never the cube's orbit")
        model.dragEnded(from: onCube, at: ScreenPoint(onCube.x + 40, onCube.y), modifiers: [], button: .primary)
        expectSameOrientation(model.pose, before)
    }

    @Test(arguments: [
        ViewportCommand.view(.top), .view(.isometric), .rotate(.left), .rotate(.up), .home, .projection(.perspective),
    ])
    func commandsThatTurnTheCameraDoNothing(_ command: ViewportCommand) {
        let model = makeModel(tool: planarTool())
        model.homePose = CameraPose(target: Vector3(5, 5, 5), distance: 50, yaw: 1, pitch: 0.2)
        let before = model.pose
        model.perform(command)
        #expect(!model.isAnimating)
        #expect(model.pose == before)
    }

    @Test func zoomKeysStillZoom() {
        let model = makeModel(tool: planarTool())
        let before = model.pose
        model.performKey(.zoomIn)
        #expect(model.pose.distance < before.distance)
        expectSameOrientation(model.pose, before)
    }

    @Test func fFramesTheToolsBoundsWithoutTurning() async {
        let tool = planarTool()
        tool.framingBounds = BoundingBox(min: Vector3(40, 40, 0), max: Vector3(60, 60, 0))
        let model = makeModel(tool: tool)
        let before = model.pose
        model.performKey(.frame)
        await model.waitForAnimation()
        expectSameOrientation(model.pose, before)
        #expect(isClose(model.pose.target, Vector3(50, 50, 0)), "centred on the tool's bounds")
    }

    @Test func theFaceMenuIsEmpty() async throws {
        let model = makeModel(tool: planarTool())
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).isEmpty, "Look At would turn the camera")
        let before = model.pose
        model.lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(2)))
        #expect(model.pose == before)
    }

    @Test func leavingRestoresOrbitAndKeepsTheCamera() {
        let model = makeModel(tool: planarTool())
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 160), modifiers: [], button: .primary)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 160), modifiers: [], button: .primary)
        let panned = model.pose
        model.tool = nil
        #expect(model.pose == panned, "leaving keeps the camera where it is")
        #expect(model.showsViewCube)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 160), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .orbit)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 160), modifiers: [], button: .primary)
        #expect(model.pose.yaw != panned.yaw)
    }

    @Test func aFreeToolKeepsTheCubeAndFramesTheScene() async throws {
        let model = makeModel(tool: RecordingTool())
        #expect(model.showsViewCube)
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        model.performKey(.frame)
        await model.waitForAnimation()
        let bounds = try #require(model.sceneBounds)
        #expect(isClose(model.pose.target, bounds.center), "F frames the scene: the tool has no bounds of its own")
        model.perform(.view(.top))
        #expect(model.isAnimating)
    }

    /// The first scene's framing (isometric, from the home view) waits for the first solid, which in a new document
    /// may arrive mid-sketch: it must never turn a camera that faces the sketch.
    @Test func theFirstSceneNeverTurnsACameraFacingThePlane() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.tool = planarTool()
        model.lookAt(.xy, framing: BoundingBox(min: Vector3(-50, -50, 0), max: Vector3(50, 50, 0)))
        await model.waitForAnimation()
        let facing = model.pose
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        await model.framingTask?.value
        #expect(model.pose == facing)
    }

    /// Any explicit camera move counts as the first framing, planar or not.
    @Test func anExplicitCameraMoveCountsAsTheFirstFraming() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.lookAt(.xy, framing: BoundingBox(min: Vector3(-50, -50, 0), max: Vector3(50, 50, 0)))
        await model.waitForAnimation()
        let facing = model.pose
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        #expect(model.pose == facing)
    }

    /// A press, scroll, pinch or key during the turn onto the plane finishes the turn: freezing it would lock an
    /// oblique view in.
    @Test(arguments: ["press", "scroll", "pinch", "key"])
    func inputDuringTheTurnOntoThePlaneFinishesIt(_ input: String) {
        let clock = ManualClock()
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, yaw: 0.7,
                                                                             pitch: 0.3), clock: clock)
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.tool = planarTool()
        model.lookAt(.xy, framing: BoundingBox(min: Vector3(-50, -50, 0), max: Vector3(50, 50, 0)))
        let target = model.pose
        clock.time += CameraAnimation.viewCubeDuration / 2
        switch input {
        case "press": model.pointerDown(at: ScreenPoint(200, 150), modifiers: [])
        case "scroll": model.scrolled(by: 0.001, at: ScreenPoint(200, 150), phase: .moving)
        case "pinch": model.pinchChanged(magnification: 1, centre: ScreenPoint(200, 150))
        default: model.performKey(.zoomIn)
        }
        #expect(!model.isAnimating)
        expectSameOrientation(model.pose, target)
        #expect(isClose(model.pose.toEye, .unitZ), "face-on")
    }

    /// While a pan or zoom moves the camera under a still or moving pointer, the tool hears where the pointer is
    /// (its rubber band and readout follow); during a scroll and a pinch too.
    @Test func panZoomAndScrollTellTheToolWhereThePointerIs() {
        let tool = planarTool()
        let model = makeModel(tool: tool)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 160), modifiers: [], button: .middle)
        #expect(tool.calls.last == "moved 230,160")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 160), modifiers: [], button: .middle)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        #expect(tool.calls.last == "moved 200,120")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        model.scrolled(by: 10, at: ScreenPoint(300, 100), phase: .moving)
        #expect(tool.calls.last == "moved 300,100")
        model.scrolled(by: 0, at: ScreenPoint(300, 100), phase: .ended)
        model.pinchChanged(magnification: 1.2, centre: ScreenPoint(120, 80))
        #expect(tool.calls.last == "moved 120,80")
        model.pinchEnded()
    }

    /// The projector carries the model area the panels leave, so a tool can keep its chrome inside it.
    @Test func theProjectorCarriesTheModelArea() {
        let tool = planarTool()
        let model = makeModel(tool: tool)
        model.setModelArea(ViewportInsets(top: 60, leading: 20))
        model.pointerHovered(at: ScreenPoint(200, 150))
        #expect(tool.lastProjector?.modelArea == ViewportInsets(top: 60, leading: 20))
    }
}
