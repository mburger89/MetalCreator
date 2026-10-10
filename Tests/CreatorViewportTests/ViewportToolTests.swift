import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// A `ViewportTool` takes the primary pointer input while it is set (sketcher spec §8), and the viewport keeps its
/// navigation.
@MainActor
struct ViewportToolTests {
    func makeModel(tool: RecordingTool?) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                                             projection: .orthographic),
                                  clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.tool = tool
        return model
    }

    @Test func aClaimedClickReachesTheToolAndNotThePicker() {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        var picked: [PickTarget?] = []
        model.events.clicked = { picked.append($0) }
        model.click(at: ScreenPoint(200, 150))
        #expect(tool.calls == ["clicked 200,150", "moved 200,150"], "then the pointer is over the release point")
        #expect(picked.isEmpty, "the tool claimed it")
        tool.claims = false
        model.click(at: ScreenPoint(210, 150))
        #expect(picked.count == 1, "an unclaimed click is reported as before")
    }

    @Test func aDeclinedClickOffersThePickToTheTool() {
        let tool = RecordingTool()
        tool.claims = false
        let model = makeModel(tool: tool)
        model.pick = { _ in .edge(solid: 0, EdgeID(3)) }
        var reported: [PickTarget?] = []
        model.events.clicked = { reported.append($0) }
        model.click(at: ScreenPoint(200, 150))
        #expect(tool.modelPicks == [.edge(solid: 0, EdgeID(3))])
        #expect(reported == [.edge(solid: 0, EdgeID(3))], "the tool left it, so the host hears it as before")
    }

    @Test func aToolThatTakesThePickKeepsItFromTheHost() {
        let tool = RecordingTool()
        tool.claims = false
        tool.claimsModel = true
        let model = makeModel(tool: tool)
        model.pick = { point in point.x < 100 ? .face(solid: 0, FaceID(1)) : nil }
        var reported: [PickTarget?] = []
        model.events.clicked = { reported.append($0) }
        model.click(at: ScreenPoint(50, 150))
        model.click(at: ScreenPoint(300, 150))
        #expect(tool.modelPicks == [.face(solid: 0, FaceID(1)), nil], "empty space is offered too")
        #expect(reported.isEmpty)
    }

    @Test func aClaimedClickIsNotOfferedAPick() {
        let tool = RecordingTool()
        tool.claimsModel = true
        let model = makeModel(tool: tool)
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        model.click(at: ScreenPoint(200, 150))
        #expect(tool.modelPicks.isEmpty, "the tool claimed the click on the plane, so there is nothing to offer")
    }

    @Test func theCubeAndTheHandlesKeepTheirClicksFromTheToolsPick() {
        let tool = RecordingTool()
        tool.claims = false
        tool.claimsModel = true
        let model = makeModel(tool: tool)
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        model.click(at: model.cubeLayout.center)
        #expect(tool.modelPicks.isEmpty)
    }

    @Test func aClaimedDragMovesNoCamera() {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        let before = model.pose
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .tool)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(240, 160), modifiers: [], button: .primary)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(250, 170), modifiers: [], button: .primary)
        #expect(tool.calls == ["began 200,150", "dragged 230,150", "dragged 240,160", "ended 250,170", "moved 250,170"])
        #expect(model.pose == before)
        #expect(model.activeDragMode == nil)
    }

    @Test func aDeclinedDragOrbitsAndNavigationStaysTheViewports() {
        let tool = RecordingTool()
        tool.claims = false
        let model = makeModel(tool: tool)
        let before = model.pose
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .orbit)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 150), modifiers: [], button: .primary)
        #expect(model.pose != before)
        tool.claims = true
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: .shift, button: .primary)
        #expect(model.activeDragMode == .pan, "Shift-drag pans without asking the tool")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 150), modifiers: .shift, button: .primary)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .secondary)
        #expect(model.activeDragMode == .orbit, "right-drag orbits")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 150), modifiers: [], button: .secondary)
        #expect(tool.calls.filter { $0.hasPrefix("began") } == ["began 200,150"], "only the plain primary drag was offered")
    }

    @Test func theCubeStaysTheViewports() {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        model.click(at: model.cubeLayout.center)
        #expect(!tool.calls.contains { $0.hasPrefix("clicked") })
        #expect(model.isAnimating)
    }

    @Test func hoverReachesTheToolAndTheCursorIsACrosshair() {
        let tool = RecordingTool()
        let model = makeModel(tool: nil)
        #expect(model.cursor == nil)
        model.tool = tool
        #expect(model.cursor == .crosshair)
        model.pointerHovered(at: ScreenPoint(100, 100))
        model.pointerHovered(at: nil)
        #expect(tool.calls == ["moved 100,100", "moved nowhere"])
        #expect(tool.lastProjector?.size == ViewportSize(width: 400, height: 300))
    }

    /// "Edit sketch" turns the camera while the user may already be drawing: when the turn ends, the tool is told the
    /// pointer is where it still is (re-mapped under the settled camera), so a rubber band in progress isn't dropped.
    @Test func theEndOfACameraTurnTellsTheToolThePointerIsStillThere() async {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        model.pose = CameraPose(target: .zero, distance: 100, yaw: 0.7, pitch: 0.3)
        model.lookAt(.xy, framing: BoundingBox(min: Vector3(-10, -10, 0), max: Vector3(10, 10, 0)))
        model.pointerHovered(at: ScreenPoint(120, 80))
        await model.waitForAnimation()
        #expect(tool.calls == ["moved 120,80", "moved 120,80"], "never \"moved nowhere\" while the pointer is over the view")
    }

    /// The face menu stays, but while a tool holds the pointer it only navigates: "Select Edges of Face" would add a
    /// node and "Show Producing Node" would change the graph's selection in the middle of a sketch.
    @Test func whileAToolIsSetTheFaceMenuOnlyLooksAt() async throws {
        let model = makeModel(tool: RecordingTool())
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(2))
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)) == [.lookAt(ref)])
        model.tool = nil
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).count == 3, "Look At, Select Edges, Show Producing Node")
    }

    @Test func theProjectorMapsScreenPointsOntoAPlaneAndBack() throws {
        let pose = CameraPose(target: Vector3(5, 5, 0), distance: 100, pitch: .pi / 2, projection: .orthographic)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: pose, size: size)
        let centre = try #require(projector.planePoint(under: size.center, on: .xy))
        #expect(abs(centre.x - 5) < 1e-9 && abs(centre.y - 5) < 1e-9, "the view's centre is over the target")
        let right = try #require(projector.planePoint(under: ScreenPoint(300, 150), on: .xy))
        #expect(abs(right.x - (5 + 100 * projector.millimetresPerPoint)) < 1e-9, "screen right is plane +x from the top")
        let back = try #require(projector.screenPoint(of: Plane.xy.point(right)))
        #expect(abs(back.x - 300) < 1e-6 && abs(back.y - 150) < 1e-6)
        let edgeOn = ViewportProjector(pose: CameraPose(distance: 100, pitch: 0, projection: .orthographic), size: size)
        #expect(edgeOn.planePoint(under: size.center, on: .xy) == nil, "a plane seen edge-on has no point under the pointer")
    }

    @Test func lookingAtAPlaneTurnsItsXAxisRightAndGoesOrthographic() async {
        let model = makeModel(tool: nil)
        model.pose = CameraPose(target: .zero, distance: 100, yaw: 0.7, pitch: 0.3)
        let plane = Plane(origin: Vector3(0, 0, 10), normal: .unitZ, xAxis: Vector3(0, 1, 0))
        model.lookAt(plane, framing: BoundingBox(min: Vector3(-10, -10, 10), max: Vector3(10, 10, 10)))
        await model.waitForAnimation()
        #expect(model.pose.projection == .orthographic)
        #expect(isClose(model.pose.toEye, .unitZ))
        #expect(isClose(model.pose.right, plane.xAxis), "the sketch's x axis points right")
    }
}
