import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// Sketch mode locks the camera to the sketch plane (user, 2026-10-09): a drag off the sketch's points pans, a drag on
/// one still moves it, the view cube is hidden, F frames the sketch without turning, and finishing gives orbit back
/// with the camera left where it is.
@MainActor
struct SketchCameraTests {
    /// Two free points, (20, 20) and (40, 30), on XY.
    func twoPoints() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xy))
        sketch.addPoint(Vector2(20, 20))
        sketch.addPoint(Vector2(40, 30))
        return sketch
    }

    func openSketch(_ sketch: Sketch) async throws -> (app: AppModel, node: Node) {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        return (app, box.sketch)
    }

    func screenPoint(_ app: AppModel, _ p: Vector2) throws -> ScreenPoint {
        try #require(ViewportProjector(pose: app.viewport.pose, size: app.viewport.viewSize).screenPoint(of: Plane.xy.point(p)))
    }

    func sameOrientation(_ a: CameraPose, _ b: CameraPose) -> Bool {
        a.yaw == b.yaw && a.pitch == b.pitch && a.projection == b.projection
    }

    @Test func aDragOffTheSketchPansAndNeverTurns() async throws {
        let (app, _) = try await openSketch(twoPoints())
        let before = app.viewport.pose
        let start = try screenPoint(app, Vector2(-30, -30))
        let end = ScreenPoint(start.x + 80, start.y + 40)
        app.viewport.dragChanged(from: start, to: end, modifiers: [], button: .primary)
        #expect(app.viewport.activeDragMode == .pan)
        app.viewport.dragEnded(from: start, at: end, modifiers: [], button: .primary)
        #expect(sameOrientation(app.viewport.pose, before))
        #expect(app.viewport.pose.target != before.target)
    }

    @Test func aDragOnAPointStillMovesIt() async throws {
        let (app, node) = try await openSketch(twoPoints())
        let editor = try #require(app.sketch?.editor)
        let before = app.viewport.pose
        let start = try screenPoint(app, Vector2(20, 20))
        let end = try screenPoint(app, Vector2(25, 15))
        app.viewport.dragChanged(from: start, to: end, modifiers: [], button: .primary)
        #expect(app.viewport.activeDragMode == .tool)
        app.viewport.dragEnded(from: start, at: end, modifiers: [], button: .primary)
        await app.settle()
        #expect(app.viewport.pose == before, "the camera stays put")
        let moved = editor.sketch.entityIDs.compactMap { editor.sketch.position(of: $0) }
        #expect(moved.contains { ($0 - Vector2(25, 15)).length < 1e-6 }, "the point followed the pointer")
        guard case .sketch(let stored)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] else {
            Issue.record("the node holds no sketch")
            return
        }
        #expect(stored == editor.sketch, "the move was stored")
    }

    @Test func theViewCubeIsHiddenAndItsCommandsDoNothing() async throws {
        let (app, _) = try await openSketch(twoPoints())
        #expect(!app.viewport.showsViewCube)
        let before = app.viewport.pose
        app.viewport.perform(.view(.isometric))
        app.viewport.perform(.rotate(.left))
        #expect(app.viewport.pose == before)
    }

    @Test func fFramesTheSketchWithoutTurning() async throws {
        let (app, _) = try await openSketch(twoPoints())
        let editor = try #require(app.sketch?.editor)
        let before = app.viewport.pose
        let start = try screenPoint(app, Vector2(-30, -30))
        app.viewport.dragChanged(from: start, to: ScreenPoint(start.x + 300, start.y), modifiers: [], button: .middle)
        app.viewport.dragEnded(from: start, at: ScreenPoint(start.x + 300, start.y), modifiers: [], button: .middle)
        #expect(app.viewport.pose.target != before.target, "panned away")
        app.viewport.performKey(.frame)
        await app.viewport.waitForAnimation()
        #expect(sameOrientation(app.viewport.pose, before))
        #expect(app.viewport.pose == CameraNavigation.frame(try #require(editor.framingBounds), before,
                                                             size: app.viewport.viewSize, insets: app.viewport.modelArea))
    }

    @Test func finishingRestoresOrbitAndKeepsTheCamera() async throws {
        let (app, _) = try await openSketch(twoPoints())
        let start = try screenPoint(app, Vector2(-30, -30))
        app.viewport.dragChanged(from: start, to: ScreenPoint(start.x + 50, start.y), modifiers: [], button: .middle)
        app.viewport.dragEnded(from: start, at: ScreenPoint(start.x + 50, start.y), modifiers: [], button: .middle)
        let panned = app.viewport.pose
        app.finishSketch()
        await app.settle()
        #expect(app.viewport.pose == panned)
        #expect(app.viewport.showsViewCube)
        app.viewport.dragChanged(from: start, to: ScreenPoint(start.x + 50, start.y), modifiers: [], button: .primary)
        #expect(app.viewport.activeDragMode == .orbit)
        app.viewport.dragEnded(from: start, at: ScreenPoint(start.x + 50, start.y), modifiers: [], button: .primary)
    }

    @Test func enteringFacesThePlaneOrthographic() async throws {
        let (app, _) = try await openSketch(twoPoints())
        #expect(app.viewport.pose.projection == .orthographic)
        #expect((app.viewport.pose.toEye - Plane.xy.normal).length < 1e-9)
    }

    /// A new document has no camera yet, so its first solid would be framed isometric: drawing the first profile
    /// mid-sketch must not turn the camera off the plane (and leave it locked there).
    @Test func theFirstSolidOfANewDocumentKeepsTheCameraOnThePlane() async throws {
        let (app, _) = try await openSketch(Sketch(plane: .fixed(.xy)))
        #expect(app.viewport.items.isEmpty, "nothing to show yet")
        let editor = try #require(app.sketch?.editor)
        editor.choose(.line)
        for corner in [Vector2(0, 0), Vector2(40, 0), Vector2(40, 30), Vector2(0, 30), Vector2(0, 0)] {
            editor.click(at: corner, tolerance: 1, modifiers: [])
        }
        await app.settle()
        await app.viewport.framingTask?.value
        await app.viewport.waitForAnimation()
        #expect(!app.viewport.items.isEmpty, "the extrusion is shown")
        #expect(app.viewport.pose.projection == .orthographic)
        #expect((app.viewport.pose.toEye - Plane.xy.normal).length < 1e-9, "still face-on")
    }
}
