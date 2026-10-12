import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// F, + and − go to the viewport over the viewport and to the graph over its canvas, and a focused field keeps them (human
/// check M6-4). Every key goes through the app's real window (the keymap, `AppInput`, the canvas's key region and the
/// focus chain), so the observable routing is pinned here; the canvas hover veto and the `Panel` key context that gap M6-e
/// named stay pinned only by the mapping tests (`AppInputTests`).
@MainActor
struct ViewportKeyRoutingWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport, not the canvas.
    let viewportSpot = Point(x: Pixels(700), y: Pixels(300))

    func open() async throws -> (app: AppWindow, rectangle: Node, canvasSpot: Point<Pixels>) {
        var builder = GraphBuilder()
        let part = builder.box(at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        return (app, part.rectangle, app.point(inCanvasView: Vector2(900, 120)))
    }

    @Test func plusAndMinusZoomTheViewportOverTheViewportAndNotTheGraph() async throws {
        let (app, _, _) = try await open()
        let pose = app.model.viewport.pose
        let zoom = app.editor.transform.zoom
        app.window.hover(at: viewportSpot)
        app.window.typeKey("+")
        #expect(app.model.viewport.pose.distance < pose.distance, "the viewport zooms in")
        app.window.typeKey("-")
        #expect(app.model.viewport.pose.distance == pose.distance, "and out again")
        #expect(app.editor.transform.zoom == zoom, "the graph never moved")
    }

    @Test func plusAndMinusZoomTheGraphOverItsCanvasAndNotTheViewport() async throws {
        let (app, _, canvasSpot) = try await open()
        let pose = app.model.viewport.pose
        let zoom = app.editor.transform.zoom
        app.window.hover(at: canvasSpot)
        app.window.typeKey("+")
        #expect(app.editor.transform.zoom > zoom, "the graph zooms in")
        app.window.typeKey("-")
        #expect(app.editor.transform.zoom == zoom, "and out again")
        #expect(app.model.viewport.pose == pose, "the viewport never moved")
    }

    @Test func fFramesTheViewportOverTheViewportAndTheGraphOverItsCanvas() async throws {
        let (app, rectangle, canvasSpot) = try await open()
        app.editor.selection = [rectangle.id]
        // The viewport frames its scene as soon as it has a size, which the window now gives it at once (gap M4-a): zoom
        // in first, so there is a framing for F to restore.
        app.window.hover(at: viewportSpot)
        app.window.typeKey("+")
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        app.window.typeKey("f")
        app.window.advance(by: 1)
        #expect(app.model.viewport.pose != pose, "the viewport frames its part")
        #expect(app.editor.transform == transform, "and the graph stays")
        let framed = app.model.viewport.pose
        app.window.hover(at: canvasSpot)
        app.window.typeKey("f")
        app.window.advance(by: 1)
        #expect(app.editor.transform != transform, "over the canvas F frames the graph's selection")
        #expect(app.model.viewport.pose == framed, "and the viewport stays")
    }

    @Test func aFocusedInspectorFieldTakesTheKeysUntilTheViewportIsPressed() async throws {
        let (app, rectangle, _) = try await open()
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [rectangle.id])
        let field = try #require(app.window.elements {
            $0.role == .textField && $0.frame.origin.x.value >= Float(app.inspectorColumnStart)
        }.first)
        try app.window.click(field)
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        app.window.hover(at: viewportSpot)
        for key: KeyEquivalent in ["f", "+", "-"] { app.window.typeKey(key) }
        #expect(app.model.viewport.pose == pose && app.editor.transform == transform, "the field has them, wherever the pointer is")
        app.window.click(at: viewportSpot)
        app.window.typeKey("+")
        #expect(app.model.viewport.pose.distance < pose.distance, "after a press on the viewport the field lets go and + zooms")
    }
}
