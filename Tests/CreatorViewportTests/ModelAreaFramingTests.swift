import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// Framing in the model area (spec §6.3, roadmap "Viewport: frame in the model area"): the first framing, F and
/// Look At centre the part in the part of the view the floating panels leave, and fit it there.
@MainActor
struct ModelAreaFramingTests {
    let size = ViewportSize(width: 800, height: 500)
    /// The app's left dock: the top bar, the graph panel on the left and the inspector on the right.
    let panels = ViewportInsets(top: 60, leading: 300, bottom: 0, trailing: 260)

    /// The model area's centre and its rectangle, in view points.
    var areaCentre: ScreenPoint {
        ScreenPoint((panels.leading + size.width - panels.trailing) / 2, (panels.top + size.height - panels.bottom) / 2)
    }

    func isInsideTheArea(_ point: ScreenPoint) -> Bool {
        point.x >= panels.leading && point.x <= size.width - panels.trailing
            && point.y >= panels.top && point.y <= size.height - panels.bottom
    }

    func makeModel(pose: CameraPose? = CameraPose(target: .zero, distance: 100, yaw: 0.6, pitch: 0.4)) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        model.setModelArea(panels)
        return model
    }

    @Test(arguments: [Projection.perspective, .orthographic])
    func framingCentresTheBoundsInTheModelAreaAndFitsEveryCorner(_ projection: Projection) throws {
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: Vector3(500, 0, 0), distance: 3, yaw: 0.8, pitch: 0.6, projection: projection)
        let framed = CameraNavigation.frame(bounds, start, size: size, insets: panels)
        #expect(framed.yaw == start.yaw && framed.pitch == start.pitch && framed.projection == projection)
        let centre = try #require(CameraMath.project(bounds.center, framed, size: size, sceneRadius: 40)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
        for corner in corners(bounds) {
            let point = try #require(CameraMath.project(corner, framed, size: size, sceneRadius: 40)).point
            #expect(isInsideTheArea(point), "\(point) is under a panel")
        }
    }

    @Test func noInsetsFrameInTheWholeViewAsBefore() {
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: .zero, distance: 3, yaw: 0.8, pitch: 0.6)
        let framed = CameraNavigation.frame(bounds, start, size: size)
        #expect(framed.target == bounds.center)
        #expect(framed == CameraNavigation.frame(bounds, start, size: size, insets: ViewportInsets()))
    }

    @Test func insetsTheViewCantHonourAreIgnored() {
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: .zero, distance: 3, yaw: 0.8, pitch: 0.6)
        let whole = CameraNavigation.frame(bounds, start, size: size)
        // Panels wider than the view, a model area thinner than a point, and an empty view: the whole view is used.
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: ViewportInsets(leading: 500, trailing: 400)) == whole)
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: ViewportInsets(top: 250, bottom: 249.5)) == whole)
        let empty = ViewportSize(width: 0, height: 0)
        #expect(CameraNavigation.frame(bounds, start, size: empty, insets: panels)
            == CameraNavigation.frame(bounds, start, size: empty))
        // Negative and non-finite sides count as none.
        let odd = ViewportInsets(top: -40, leading: .nan, bottom: .infinity, trailing: 0)
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: odd) == whole)
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: odd).isFinite)
    }

    @Test func theFirstFramingCentresThePartInTheModelArea() async throws {
        let model = makeModel(pose: nil)
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
        for corner in corners(box.bounds) {
            #expect(isInsideTheArea(try #require(CameraMath.project(corner, model.pose, size: size)).point))
        }
    }

    @Test func fFramesThePartInTheModelArea() async throws {
        let model = makeModel()
        let box = try await fakeBox(width: 80)
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        model.performKey(.frame)
        await model.waitForAnimation()
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
        for corner in corners(box.bounds) {
            #expect(isInsideTheArea(try #require(CameraMath.project(corner, model.pose, size: size)).point))
        }
    }

    @Test func lookAtCentresTheFaceInTheModelArea() async throws {
        let model = makeModel()
        model.show([ViewportItem(solid: try await fakeBox(width: 80))])
        await model.waitForMeshes()
        model.choose(.lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(3))))
        await model.waitForAnimation()
        #expect(isClose(model.pose.toEye, .unitX), "the right face looks along +X")
        // The right face is 20 × 30 at x = 40, centred on (40, 0, 15).
        let centre = try #require(CameraMath.project(Vector3(40, 0, 15), model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
    }

    /// The arrows, the cube's regions and a cube drag turn the camera about the point shown at the model area's
    /// centre, not about the target (which framing moved off the part), so the part stays in the model area instead
    /// of swinging under a panel.
    @Test func theArrowsTheCubeAndACubeDragTurnThePartWhereItIs() async throws {
        let model = makeModel(pose: nil)
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        func partCentre() throws -> ScreenPoint {
            try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        }
        let commands: [ViewportCommand] = [.rotate(.right), .rotate(.up), .rotate(.right), .view(.front), .view(.isometric)]
        for command in commands {
            model.perform(command)
            await model.waitForAnimation()
            #expect(isClose(try partCentre(), areaCentre, tolerance: 1e-6), "after \(command)")
        }
        let cube = model.cubeLayout.center
        model.pointerDown(at: cube, modifiers: [])
        model.pointerDragged(to: ScreenPoint(cube.x + 30, cube.y + 12))
        model.pointerUp(at: ScreenPoint(cube.x + 30, cube.y + 12))
        #expect(isClose(try partCentre(), areaCentre, tolerance: 1e-6), "after a cube drag")
    }

    @Test func keyZoomWithoutAPointerZoomsTowardTheModelAreaCentre() async throws {
        let model = makeModel(pose: nil)
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let framed = model.pose
        model.performKey(.zoomIn)
        #expect(isClose(model.pose.distance, framed.distance / ViewportInputMap.keyZoomFactor))
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-6))
    }
}
