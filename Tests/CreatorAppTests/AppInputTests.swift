import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import MetalUI
import Testing
@testable import CreatorApp

/// The window's key routing, as far as it can be pinned without a real `Window` (its initializer is internal):
/// the keymap and its contexts, and what `onAction` and `onInput` do. The routing through a window is human
/// checks M6-4 and M6-5.
@MainActor
struct AppInputTests {
    @Test func theViewportsKeysAreOutOfScopeWhileFocusIsInAPanel() throws {
        let bindings = AppInput.keymap.bindings
        #expect(bindings.map(\.spelling) == ["f", "=", "shift-+", "+", "-", "up", "down", "tab"])
        #expect(bindings.prefix(5).allSatisfy { $0.action is ViewportKeyAction && $0.context == AppKeyContext.viewport })
        #expect(bindings.suffix(3).allSatisfy { $0.context == nil })
        let predicate = try #require(ContextPredicate.parse(AppKeyContext.viewport))
        #expect(predicate.evaluate(against: []), "nothing focused: F, + and − reach the viewport")
        #expect(!predicate.evaluate(against: [KeyContext(AppKeyContext.panel)]), "a focused inspector or palette field types them")
    }

    @Test func theViewportsKeysYieldToTheGraphOverItsCanvas() async {
        let app = await makeApp()
        let input = AppInput(model: app)
        let before = app.viewport.pose
        #expect(input.handleAction(ViewportKeyAction(command: .zoomIn)))
        #expect(app.viewport.pose.distance < before.distance)
        app.editor.pointerLocation = Vector2(40, 40)
        let zoomed = app.viewport.pose
        #expect(!input.handleAction(ViewportKeyAction(command: .zoomIn)), "unclaimed: + goes on to the graph's zoom")
        #expect(!input.handleAction(ViewportKeyAction(command: .zoomOut)), "and − too")
        #expect(app.viewport.pose == zoomed)
        #expect(!input.handleAction(ViewportKeyAction(command: .frame)), "F goes on to the graph's own F")
    }

    /// Spec 2026-10-09 §3: "F frames the selection in the graph canvas when the pointer is over it (the viewport's F
    /// is unchanged)".
    @Test func fFramesTheGraphOverItsCanvasAndTheViewportElsewhere() async throws {
        let app = await makeApp()
        let input = AppInput(model: app)
        let node = BuiltInNodes.registry.makeNode(NumberNode.typeID, at: Vector2(2000, 2000))
        try app.document.perform(.addNode(node))
        app.editor.selection = [node.id]
        let canvas = app.editor.transform
        #expect(input.handleAction(ViewportKeyAction(command: .frame)), "the pointer elsewhere: the viewport frames")
        #expect(app.editor.transform == canvas)
        app.editor.pointerLocation = Vector2(40, 40)
        #expect(!input.handleAction(ViewportKeyAction(command: .frame)))
        let f = KeyEvent(charactersIgnoringModifiers: "f", characters: "f", timestamp: 1)
        #expect(input.handleInput(.keyDown(f)))
        #expect(app.editor.transform != canvas)
    }

    @Test func theGraphsActionsComeFirst() async {
        let app = await makeApp()
        let input = AppInput(model: app)
        app.editor.openPalette()
        #expect(input.handleAction(PaletteMove(step: 1)))
        #expect(!input.handleAction(GraphTab()), "the palette is already open")
    }

    @Test func theGraphsKeysArriveThroughTheInputFallback() async throws {
        let app = await makeApp()
        let input = AppInput(model: app)
        let node = BuiltInNodes.registry.makeNode(NumberNode.typeID)
        try app.document.perform(.addNode(node))
        app.editor.selection = [node.id]
        let delete = KeyEvent(charactersIgnoringModifiers: "\u{7f}", characters: "\u{7f}", timestamp: 1)
        #expect(input.handleInput(.keyDown(delete)))
        #expect(app.document.graph.nodes.isEmpty)
    }
}
