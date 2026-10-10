import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// Double-clicking the Sketch node opens its sketch (sketcher spec §8): the graph panel's double click presses the
/// real node's "Edit sketch" button, which the app turns into sketch mode as it does the button.
@MainActor
struct SketchDoubleClickTests {
    @Test func doubleClickingTheSketchNodeEntersSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.nodeDoubleClicked(box.sketch.id)
        let request = try #require(app.editor.inspectorRequest)
        #expect(request.action == .editSketch && request.node == box.sketch.id)
        app.handle(request)
        #expect(app.sketch?.node == box.sketch.id)
    }

    @Test func doubleClickingAnotherNodeAsksNothing() async {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.nodeDoubleClicked(box.extrude.id)
        #expect(app.editor.inspectorRequest == nil)
        #expect(app.sketch == nil)
    }

    /// Errata (S5b): while a sketch is open, a double click on its own Sketch node or on another one changes nothing:
    /// the same session and editor, its stroke in progress, and the camera where the user panned it (a restart would
    /// look at the plane again).
    @Test func aDoubleClickWhileSketchingChangesNothing() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let other = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        let session = try #require(app.sketch)
        let start = ScreenPoint(100, 100)
        app.viewport.dragChanged(from: start, to: ScreenPoint(180, 140), modifiers: [], button: .primary)
        app.viewport.dragEnded(from: start, at: ScreenPoint(180, 140), modifiers: [], button: .primary)
        session.editor.choose(.line)
        session.editor.click(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        let stroke = session.editor.drawState
        let camera = app.viewport.pose
        for node in [box.sketch.id, other.sketch.id] {
            app.editor.nodeDoubleClicked(node)
            app.handle(try #require(app.editor.inspectorRequest))
            await app.viewport.waitForAnimation()
            #expect(app.sketch === session && app.sketch?.editor === session.editor)
            #expect(session.editor.drawState == stroke && stroke != .idle, "the line in progress is kept")
            #expect(app.viewport.pose == camera, "nothing looks at the plane again")
        }
    }
}
