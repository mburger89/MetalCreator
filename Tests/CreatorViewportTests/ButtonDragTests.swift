import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// MetalUI C7's drags (spec §9, docs/metalui-gaps.md C7 items 3 and 5): the right button orbits, the middle
/// button pans, and a primary drag reads its modifiers from the drag's own value.
@MainActor
struct ButtonDragTests {
    let size = ViewportSize(width: 400, height: 300)

    func makeModel(pose: CameraPose) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        return model
    }

    /// One drag as MetalUI reports it: a change at each point after the press, then the end at the last.
    func drag(_ model: ViewportModel, _ button: ViewportPointerButton, from start: ScreenPoint, through points: [ScreenPoint],
              modifiers: ViewportModifiers = []) {
        for point in points { model.dragChanged(from: start, to: point, modifiers: modifiers, button: button) }
        model.dragEnded(from: start, at: points.last ?? start, modifiers: modifiers, button: button)
    }

    @Test func aMiddleDragPansWhateverIsHeld() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        drag(model, .middle, from: ScreenPoint(200, 150), through: [ScreenPoint(215, 150), ScreenPoint(230, 150)],
             modifiers: .option)
        #expect(isClose(try #require(CameraMath.project(start.target, model.pose, size: size)).point, ScreenPoint(230, 150)))
        #expect(model.pose.distance == start.distance, "⌥ doesn't turn a middle drag into a zoom")
    }

    @Test func aRightDragOrbitsAboutThePointUnderThePointer() async throws {
        let model = makeModel(pose: CameraPose(target: Vector3(0, 0, 15), distance: 80, yaw: 0, pitch: 0))
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let press = ScreenPoint(215, 135)   // over the front face, off its quad diagonal
        let ray = CameraMath.ray(through: press, model.pose, size: size)
        let hit = try #require(MeshRaycast.nearest(ray, in: [(solidIndex: 0, mesh: TestMeshes.box(box.bounds))]))
        drag(model, .secondary, from: press, through: [ScreenPoint(240, 120), ScreenPoint(260, 110)], modifiers: .shift)
        #expect(!isClose(model.pose.yaw, 0), "Shift doesn't turn a right drag into a pan")
        #expect(isClose(try #require(CameraMath.project(hit.point, model.pose, size: size)).point, press, tolerance: 1e-9))
    }

    @Test func aRightDragOnTheCubeOrbitsAboutTheTarget() {
        let start = CameraPose(target: Vector3(1, 1, 1), distance: 100, yaw: 0.3, pitch: 0.2)
        let model = makeModel(pose: start)
        let centre = model.cubeLayout.center
        drag(model, .secondary, from: centre, through: [ScreenPoint(centre.x + 30, centre.y)])
        #expect(isClose(model.pose.yaw, 0.3 - 30 * ViewportInputMap.orbitRadiansPerPoint))
        #expect(model.pose.target == start.target)
        #expect(!model.isAnimating, "a drag on the cube never picks a region")
    }

    @Test func aRightDragOnAHandleOrbitsInsteadOfEditingIt() {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                              projection: .orthographic)
        let model = makeModel(pose: pose)
        model.showHandles([ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0...100,
                                          style: .linear, tint: .solid),
        ])
        var reports = 0
        model.events.handleChanged = { _, _, _ in reports += 1 }
        drag(model, .secondary, from: ScreenPoint(200, 75), through: [ScreenPoint(230, 75)])
        #expect(reports == 0)
        #expect(model.handles[0].value == 10)
        #expect(model.pose != pose)
    }

    @Test func aPrimaryDragTakesItsModeFromItsOwnModifiers() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        drag(model, .primary, from: ScreenPoint(200, 150), through: [ScreenPoint(230, 150)], modifiers: .shift)
        #expect(isClose(try #require(CameraMath.project(start.target, model.pose, size: size)).point, ScreenPoint(230, 150)))
        let panned = model.pose
        drag(model, .primary, from: ScreenPoint(200, 150), through: [ScreenPoint(200, 100)], modifiers: .option)
        #expect(isClose(model.pose.distance, 100 / exp(0.5)))
        #expect(model.pose.yaw == panned.yaw)
    }

    @Test func aSecondButtonDuringADragIsIgnored() {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        let press = ScreenPoint(200, 150)
        model.dragChanged(from: press, to: ScreenPoint(220, 150), modifiers: [], button: .secondary)
        let orbited = model.pose
        model.dragChanged(from: press, to: ScreenPoint(260, 150), modifiers: [], button: .middle)
        model.dragEnded(from: press, at: ScreenPoint(260, 150), modifiers: [], button: .middle)
        #expect(model.pose == orbited, "the middle button neither pans nor ends the right drag")
        #expect(settled.isEmpty)
        model.dragEnded(from: press, at: ScreenPoint(220, 150), modifiers: [], button: .secondary)
        #expect(settled == [orbited])
    }

    /// A drag whose release never arrived (the window lost the pointer) doesn't swallow the next drag of its button.
    @Test func aDragThatLostItsReleaseEndsWhenItsButtonDragsAgain() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        let lost = model.pose
        drag(model, .middle, from: ScreenPoint(100, 100), through: [ScreenPoint(130, 100)])
        #expect(settled.first == lost, "the stale drag settled where it was")
        #expect(settled.count == 2)
        #expect(!model.isPointerDown)
        let target = try #require(CameraMath.project(start.target, model.pose, size: size)).point
        #expect(isClose(target, ScreenPoint(250, 150)), "both pans moved the scene: 20 + 30 points")
    }

    /// A right or middle drag whose release was lost doesn't swallow the primary button's drags: MetalUI forms the
    /// primary arena on every primary press, apart from the button arena (`CI-F` item 3), so its values arrive.
    @Test func aPrimaryDragAfterALostMiddleReleaseStillOrbits() {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        let lost = model.pose
        drag(model, .primary, from: ScreenPoint(100, 100), through: [ScreenPoint(130, 100)])
        #expect(isClose(model.pose.yaw, lost.yaw - 30 * ViewportInputMap.orbitRadiansPerPoint), "the primary drag orbited")
        #expect(settled == [lost, model.pose], "the stale pan settled where it was, then the orbit")
        #expect(!model.isPointerDown)
    }
}
