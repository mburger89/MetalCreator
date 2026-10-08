import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

@MainActor
struct ViewportModelTests {
    let size = ViewportSize(width: 400, height: 300)

    func makeModel(pose: CameraPose? = nil, kernel: StubMeshKernel = StubMeshKernel()) -> (ViewportModel, StubMeshKernel, ManualClock) {
        let clock = ManualClock()
        let model = ViewportModel(kernel: kernel, pose: pose, clock: clock)
        model.viewSize = size
        return (model, kernel, clock)
    }

    func show(_ model: ViewportModel, _ items: [ViewportItem]) async {
        model.show(items)
        await model.waitForMeshes()
    }

    @Test func showingASceneMeshesItAndFramesItOnce() async throws {
        let (model, kernel, _) = makeModel()
        let box = try await fakeBox()
        await show(model, [ViewportItem(solid: box)])
        #expect(model.sceneGeneration == 1)
        #expect(await kernel.tessellations == 1)
        #expect(model.meshError == nil)
        #expect(isClose(model.pose.target, box.bounds.center))
        #expect(model.pose.projection == .perspective)
        for corner in corners(box.bounds) {
            let point = try #require(CameraMath.project(corner, model.pose, size: size, sceneRadius: 20)).point
            #expect(point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height)
        }
        let framed = model.pose
        await show(model, [ViewportItem(solid: box, isGhost: true)])
        #expect(model.pose == framed, "only the first scene is framed")
        #expect(await kernel.tessellations == 1, "the same solid is not tessellated again")
        #expect(model.sceneGeneration == 2)
        #expect(model.frame(at: 0).items.first?.isGhost == true)
    }

    @Test func aSavedCameraIsKept() async throws {
        let saved = CameraPose(target: Vector3(9, 9, 9), distance: 33, yaw: 1, pitch: 0.2)
        let (model, _, _) = makeModel(pose: saved)
        await show(model, [ViewportItem(solid: try await fakeBox())])
        #expect(model.pose == saved)
    }

    @Test func aSupersededSceneNeverReplacesTheNewerOne() async throws {
        let (model, _, _) = makeModel()
        let first = try await fakeBox(width: 10)
        let second = try await fakeBox(width: 50)
        model.show([ViewportItem(solid: first)])
        model.show([ViewportItem(solid: second)])
        await model.waitForMeshes()
        let frame = model.frame(at: 0)
        #expect(frame.items.count == 1)
        #expect(frame.items.first.flatMap { MeshQueries.bounds($0.mesh) } == second.bounds)
        #expect(model.items.map { ObjectIdentifier($0.solid) } == [ObjectIdentifier(second)])
        #expect(model.sceneGeneration == 1)
    }

    @Test func theShownSceneStaysUpUntilTheNewOneHasMeshes() async throws {
        let kernel = StubMeshKernel()
        let (model, _, _) = makeModel(kernel: kernel)
        let first = try await fakeBox(width: 10)
        let second = try await fakeBox(width: 50)
        await show(model, [ViewportItem(solid: first)])
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        let shownSerial = try #require(model.frame(at: 0).items.first?.meshSerial)

        // The load task can't start until this test suspends, so this is exactly what a redraw sees between
        // `show` and the meshes arriving. A handle drag changes `handles` (and so `renderKey`) in that window.
        model.show([ViewportItem(solid: second)])
        model.showHandles([ViewportHandle(id: "h", anchor: .zero, direction: .unitZ, value: 5, range: 0...10,
                                          style: .linear, tint: .solid)])
        #expect(model.frame(at: 0).items.map(\.meshSerial) == [shownSerial], "the old part stays drawn")
        #expect(model.items.map { ObjectIdentifier($0.solid) } == [ObjectIdentifier(first)])
        #expect(model.sceneBounds == first.bounds)
        #expect(model.hovered == .face(solid: 0, FaceID(2)), "the pick still describes the drawn part")
        #expect(model.sceneGeneration == 1)

        model.pick = { _ in .face(solid: 0, FaceID(4)) }
        await model.waitForMeshes()
        #expect(model.items.map { ObjectIdentifier($0.solid) } == [ObjectIdentifier(second)])
        let swapped = try #require(model.frame(at: 0).items.first)
        #expect(swapped.meshSerial != shownSerial)
        #expect(MeshQueries.bounds(swapped.mesh) == second.bounds)
        #expect(model.sceneBounds == second.bounds)
        #expect(model.sceneGeneration == 2)
        #expect(model.hovered == .face(solid: 0, FaceID(4)), "re-picked against the new part in the same step")

        // A failed load keeps the shown part too.
        await kernel.setFailing(true)
        await show(model, [ViewportItem(solid: first)])
        #expect(model.meshError != nil)
        #expect(model.items.map { ObjectIdentifier($0.solid) } == [ObjectIdentifier(second)])
        #expect(model.frame(at: 0).items.map(\.meshSerial) == [swapped.meshSerial])
        #expect(model.sceneGeneration == 2)
    }

    @Test func aSceneShownBeforeTheFirstDrawIsFramedOnceTheViewHasASize() async throws {
        let (model, _, _) = makeModel()
        model.viewSize = ViewportSize(width: 0, height: 0)
        let box = try await fakeBox()
        await show(model, [ViewportItem(solid: box)])
        #expect(model.pose == CameraPose(), "not framed for a view with no size")
        // A narrow view: framed for aspect 1, the part's sides would be clipped.
        let narrow = ViewportSize(width: 120, height: 600)
        model.recordViewSize(narrow)
        await model.framingTask?.value
        #expect(isClose(model.pose.target, box.bounds.center))
        for corner in corners(box.bounds) {
            let point = try #require(CameraMath.project(corner, model.pose, size: narrow, sceneRadius: 20)).point
            #expect(point.x >= 0 && point.x <= narrow.width && point.y >= 0 && point.y <= narrow.height)
        }
        let framed = model.pose
        model.recordViewSize(ViewportSize(width: 0, height: 0))
        model.recordViewSize(narrow)
        await model.framingTask?.value
        #expect(model.pose == framed, "framed once")
    }

    @Test func aTessellationFailureIsReportedPlainly() async throws {
        let (model, _, _) = makeModel(pose: CameraPose(), kernel: StubMeshKernel(failing: true))
        await show(model, [ViewportItem(solid: try await fakeBox())])
        #expect(model.meshError == "Tessellate failed: the mesh could not be built.")
        #expect(model.sceneGeneration == 0)
        #expect(model.frame(at: 0).items.isEmpty)
    }

    @Test func framingOrGoingHomeWithNothingShownDoesNothing() {
        let start = CameraPose(target: Vector3(1, 2, 3), distance: 40)
        let (model, _, _) = makeModel(pose: start)
        model.perform(.frame)
        model.perform(.home)
        #expect(model.pose == start)
        #expect(!model.isAnimating)
    }

    @Test func fFramesTheSelectionBeforeEverything() async throws {
        let (model, _, _) = makeModel(pose: CameraPose(distance: 500))
        await show(model, [ViewportItem(solid: try await fakeBox(), selectedFaces: [FaceID(5)])])
        model.performKey(.frame)
        await model.waitForAnimation()
        #expect(isClose(model.pose.target, Vector3(-5, 0, 15)), "the left face's centre")
        await show(model, [ViewportItem(solid: try await fakeBox())])
        model.performKey(.frame)
        await model.waitForAnimation()
        #expect(isClose(model.pose.target, Vector3(0, 0, 15)))
    }

    @Test func aCubeFaceAnimatesToItInOrthographic() async {
        let (model, _, clock) = makeModel(pose: CameraPose(target: .zero, distance: 100, yaw: 0.3, pitch: 0.2))
        model.perform(.view(.front))
        #expect(model.isAnimating)
        #expect(model.renderKey.isAnimating)
        #expect(model.pose.projection == .orthographic)
        #expect(isClose(model.pose.toEye, Vector3(0, -1, 0)))
        let midway = model.presentedPose(at: clock.time + CameraAnimation.viewCubeDuration / 2)
        #expect(midway.yaw > 0 && midway.yaw < 0.3)
        await model.waitForAnimation()
        #expect(!model.isAnimating)
        #expect(model.presentedPose(at: clock.time) == model.pose)
    }

    @Test func arrowsAndHomeAnimate() async throws {
        let (model, _, _) = makeModel(pose: CameraPose(target: .zero, distance: 100))
        model.perform(.setHome)
        let home = try #require(model.homePose)
        model.perform(.rotate(.up))
        await model.waitForAnimation()
        #expect(isClose(model.pose.toEye, .unitZ))
        model.perform(.home)
        await model.waitForAnimation()
        #expect(model.pose == home)
    }

    @Test func goingHomeWithoutOneShowsTheIsometricFraming() async throws {
        let (model, _, _) = makeModel(pose: CameraPose(target: Vector3(100, 0, 0), distance: 5))
        let box = try await fakeBox()
        await show(model, [ViewportItem(solid: box)])
        model.perform(.home)
        await model.waitForAnimation()
        #expect(isClose(model.pose.toEye, ViewCubeRegion.isometric.direction))
        #expect(isClose(model.pose.target, box.bounds.center))
        #expect(model.pose.projection == .perspective)
    }

    @Test func projectionAndShadingSwitch() {
        let (model, _, _) = makeModel(pose: CameraPose())
        model.perform(.projection(.orthographic))
        model.perform(.shading(.shaded))
        #expect(model.pose.projection == .orthographic)
        #expect(model.shading == .shaded)
        #expect(model.frame(at: 0).shading == .shaded)
    }

    @Test func keyZoomGoesTowardTheLastHoverPoint() throws {
        let pose = CameraPose(target: .zero, distance: 100, yaw: 0.4, pitch: 0.3)
        let (model, _, _) = makeModel(pose: pose)
        let cursor = ScreenPoint(320, 80)
        model.pointerHovered(at: cursor)
        let ray = CameraMath.ray(through: cursor, pose, size: size)
        let underCursor = ray.point(at: (pose.target - ray.origin).dot(pose.toEye) / ray.direction.dot(pose.toEye))
        model.performKey(.zoomIn)
        #expect(isClose(model.pose.distance, 100 / ViewportInputMap.keyZoomFactor))
        #expect(isClose(try #require(CameraMath.project(underCursor, model.pose, size: size)).point, cursor, tolerance: 1e-9))
        model.pointerHovered(at: nil)
        let target = model.pose.target
        model.performKey(.zoomOut)
        #expect(isClose(model.pose.distance, 100))
        #expect(model.pose.target == target)
    }

    @Test func ghostsSelectionAndHoverReachTheFrame() async throws {
        let (model, _, _) = makeModel(pose: CameraPose())
        await show(model, [ViewportItem(solid: try await fakeBox()),
                           ViewportItem(solid: try await fakeBox(width: 3), isGhost: true, selectedFaces: [FaceID(2)],
                                        selectedEdges: [EdgeID(1)])])
        model.pick = { _ in .face(solid: 1, FaceID(4)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        let frame = model.frame(at: 0)
        #expect(frame.items.map(\.solidIndex) == [0, 1])
        #expect(frame.items[0].hoveredFace == nil)
        #expect(frame.items[1].hoveredFace == FaceID(4))
        #expect(frame.items[1].isGhost)
        #expect(frame.items[1].selectedFaces == [FaceID(2)])
        #expect(frame.items[1].selectedEdges == [EdgeID(1)])
        #expect(frame.gridSpacing.isFinite && frame.gridSpacing > 0)
        #expect(frame.sceneBounds == model.sceneBounds)
    }
}
