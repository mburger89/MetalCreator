import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// A double click on the graph canvas, through the app's real window: the count is the platform's (MetalUI C16,
/// `DragGesture.Value.clickCount`, gap S5-b), so what the canvas does with a double click follows the window's clicks, not
/// a timer of the editor's. `TestWindow.doubleClick(at:)` sends the second press with click count 2, as AppKit does.
@MainActor
struct CanvasDoubleClickWindowTests {
    func open() async throws -> (app: AppWindow, sketch: Node, spot: Point<Pixels>) {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await AppWindow.open(builder.graph)
        return (app, box.sketch, app.point(inCanvas: Vector2(60, 40)))
    }

    @Test func aDoubleClickOnTheSketchNodeOpensItsSketch() async throws {
        let (app, sketch, spot) = try await open()
        app.window.doubleClick(at: spot)
        await app.model.settle()
        #expect(app.model.sketch?.node == sketch.id)
    }

    @Test func twoSeparateClicksDoNot() async throws {
        let (app, sketch, spot) = try await open()
        app.window.click(at: spot)
        app.window.click(at: spot)
        await app.model.settle()
        #expect(app.model.sketch == nil && app.editor.inspectorRequest == nil)
        #expect(app.editor.selection == [sketch.id])
    }

    /// However slow the user's double click is, the platform's count decides: the editor keeps no time of its own.
    @Test func aSlowDoubleClickTheSystemCountsStillOpensIt() async throws {
        let (app, sketch, spot) = try await open()
        app.window.click(at: spot)
        app.window.advance(by: 5)
        app.window.send(.mouseDown(MouseEvent(position: spot, clickCount: 2)))
        app.window.send(.mouseUp(MouseEvent(position: spot, clickCount: 2)))
        app.window.tick()
        await app.model.settle()
        #expect(app.model.sketch?.node == sketch.id)
    }

    @Test func aDoubleClickWithShiftHeldOnlyExtendsTheSelection() async throws {
        let (app, _, spot) = try await open()
        app.window.doubleClick(at: spot, modifierFlags: .shift)
        await app.model.settle()
        #expect(app.model.sketch == nil)
    }
}
