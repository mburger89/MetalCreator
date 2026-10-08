import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

@MainActor
struct ViewportInputTests {
    let size = ViewportSize(width: 400, height: 300)

    func makeModel(pose: CameraPose) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        return model
    }

    @Test func clickingTheCubeLooksAtTheRegionUnderThePointer() {
        let model = makeModel(pose: CameraPose(target: .zero, distance: 100, yaw: 0.3, pitch: 0.2))
        let centre = model.cubeLayout.center
        model.pointerDown(at: centre, modifiers: [])
        model.pointerUp(at: centre)
        #expect(model.isAnimating)
        #expect(isClose(model.pose.toEye, Vector3(0, -1, 0)))
        #expect(model.pose.projection == .orthographic)
    }

    @Test func draggingTheCubeOrbitsWithoutAClick() {
        let start = CameraPose(target: Vector3(1, 1, 1), distance: 100, yaw: 0.3, pitch: 0.2)
        let model = makeModel(pose: start)
        let centre = model.cubeLayout.center
        model.pointerDown(at: centre, modifiers: [])
        model.pointerDragged(to: ScreenPoint(centre.x + 30, centre.y))
        model.pointerUp(at: ScreenPoint(centre.x + 30, centre.y))
        #expect(!model.isAnimating)
        #expect(isClose(model.pose.yaw, 0.3 - 30 * ViewportInputMap.orbitRadiansPerPoint))
        #expect(model.pose.target == start.target, "the cube orbits about the target")
        #expect(model.pose.projection == .perspective)
    }

    @Test func shiftDragPansAndOptionDragZooms() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: .shift)
        model.pointerDragged(to: ScreenPoint(230, 150))
        model.pointerUp(at: ScreenPoint(230, 150))
        #expect(isClose(try #require(CameraMath.project(start.target, model.pose, size: size)).point, ScreenPoint(230, 150)))
        let panned = model.pose
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: .option)
        model.pointerDragged(to: ScreenPoint(200, 100))
        model.pointerUp(at: ScreenPoint(200, 100))
        #expect(isClose(model.pose.distance, 100 / exp(0.5)))
        #expect(model.pose.yaw == panned.yaw)
    }

    @Test func aPlainDragOrbitsAboutThePointUnderThePointer() async throws {
        let model = makeModel(pose: CameraPose(target: Vector3(0, 0, 15), distance: 80, yaw: 0, pitch: 0))
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let press = ScreenPoint(215, 135)   // over the front face, off its quad diagonal
        let ray = CameraMath.ray(through: press, model.pose, size: size)
        let hit = try #require(MeshRaycast.nearest(ray, in: [(solidIndex: 0, mesh: TestMeshes.box(box.bounds))]))
        #expect(hit.face == FaceID(2))
        model.pointerDown(at: press, modifiers: [])
        model.pointerDragged(to: ScreenPoint(260, 110))
        model.pointerUp(at: ScreenPoint(260, 110))
        #expect(!isClose(model.pose.yaw, 0))
        #expect(isClose(try #require(CameraMath.project(hit.point, model.pose, size: size)).point, press, tolerance: 1e-9))
    }

    @Test func aClickReportsThePickAndLeavesTheCameraAlone() {
        let start = CameraPose(target: .zero, distance: 100)
        let model = makeModel(pose: start)
        var clicked: PickTarget??
        model.pick = { _ in .edge(solid: 0, EdgeID(3)) }
        model.events.clicked = { clicked = $0 }
        model.pointerDown(at: ScreenPoint(200, 200), modifiers: [])
        model.pointerDragged(to: ScreenPoint(201, 201))
        model.pointerUp(at: ScreenPoint(201, 201))
        #expect(clicked == .some(.edge(solid: 0, EdgeID(3))))
        #expect(model.pose == start)
    }

    @Test func hoverAsksThePickerOrTheCube() {
        let model = makeModel(pose: CameraPose(target: .zero, distance: 100))
        var asked = 0
        model.pick = { _ in
            asked += 1
            return .face(solid: 0, FaceID(1))
        }
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.hovered == .face(solid: 0, FaceID(1)))
        #expect(model.hoveredCubeRegion == nil)
        model.pointerHovered(at: model.cubeLayout.center)
        #expect(model.hovered == nil)
        #expect(model.hoveredCubeRegion == .front)
        #expect(asked == 1, "the cube is hit-tested on the CPU")
        model.pointerHovered(at: nil)
        #expect(model.hovered == nil && model.hoveredCubeRegion == nil)
    }

    @Test func draggingAHandleEditsItsValueAndNotTheCamera() {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                              projection: .orthographic)
        let model = makeModel(pose: pose)
        model.showHandles([ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0...100,
                                          style: .linear, tint: .solid)])
        var reports: [(id: String, value: Double, phase: HandleDragPhase)] = []
        model.events.handleChanged = { reports.append(($0, $1, $2)) }
        // 40 mm tall in 300 points: the knob at z = 10 is 75 points above the centre.
        model.pointerDown(at: ScreenPoint(200, 75), modifiers: [])
        model.pointerDragged(to: ScreenPoint(200, 45))
        model.pointerUp(at: ScreenPoint(200, 45))
        #expect(model.pose == pose)
        #expect(isClose(model.handles[0].value, 14))
        #expect(reports.map { $0.phase } == [.changed, .ended])
        #expect(reports.allSatisfy { $0.id == "extrude" && isClose($0.value, 14) })
    }

    @Test func aZeroSizeViewIgnoresPointerInput() {
        let start = CameraPose(target: Vector3(1, 2, 3), distance: 50)
        let model = makeModel(pose: start)
        model.viewSize = ViewportSize(width: 0, height: 0)
        model.showHandles([ViewportHandle(id: "h", anchor: .zero, direction: .unitZ, value: 5, range: 0...10,
                                          style: .linear, tint: .solid)])
        model.pointerHovered(at: ScreenPoint(200, 200))
        model.pointerDown(at: ScreenPoint(200, 200), modifiers: .shift)
        model.pointerDragged(to: ScreenPoint(260, 240))
        model.pointerUp(at: ScreenPoint(260, 240))
        model.pointerDown(at: ScreenPoint(200, 200), modifiers: .option)
        model.pointerDragged(to: ScreenPoint(.nan, .nan))
        model.pointerUp(at: ScreenPoint(200, 240))
        model.performKey(.zoomIn)
        model.performKey(.frame)
        #expect(model.pose.isFinite)
        #expect(model.pose.target == start.target)
        #expect(model.handles[0].value == 5)
        #expect(model.frame(at: 0).gridSpacing.isFinite)
    }
}
