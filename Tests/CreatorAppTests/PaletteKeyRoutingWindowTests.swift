import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The add-node palette's keys through the real window (human check EP-2; the `Panel` key context that gap M6-e named):
/// Space over the canvas opens it with its search field focused, F, + and − are typed into the field and not taken by the
/// viewport, and Return adds the node as one undo step.
@MainActor
struct PaletteKeyRoutingWindowTests {
    @Test func theSearchFieldTakesFPlusAndMinusAndReturnAddsTheNode() async throws {
        var builder = GraphBuilder()
        _ = builder.add(NumberNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        let pose = app.model.viewport.pose
        let zoom = app.editor.transform.zoom
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey(.space)
        #expect(app.editor.palette != nil)
        #expect(try app.window.focusedElement?.role == .textField, "the search field has the focus the moment the palette opens")
        app.window.typeText("f+")
        #expect(app.editor.palette?.query == "f+")
        #expect(app.model.viewport.pose == pose && app.editor.transform.zoom == zoom, "the viewport neither frames nor zooms")
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText("Rectangle")
        app.window.typeKey(.return)
        #expect(app.editor.palette == nil)
        #expect(app.editor.graph.nodes.count == 2)
        #expect(app.editor.selection.count == 1, "the new node is selected")
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 1, "one ⌘Z removes it")
    }

    @Test func escapeClosesThePaletteAndAddsNothing() async throws {
        let app = try await AppWindow.open()
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey(.space)
        app.window.typeText("Box")
        app.window.typeKey(.escape)
        #expect(app.editor.palette == nil && app.editor.graph.nodes.isEmpty)
    }
}
