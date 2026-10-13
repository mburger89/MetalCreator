import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// While a comment is being typed the graph's keys stand aside, and afterwards they act again where they should (human
/// check CT-4; MetalUI C9's key regions, gap M5-b). Every key goes through the app's real window.
@MainActor
struct CanvasTypingKeysWindowTests {
    let fixture = TypingFixture()

    /// The app with the note being edited, the pointer over the canvas.
    func editing() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.id == fixture.note.id)
        return app
    }

    @Test func deleteAndTheArrowsEditTheTextAndMoveNoNode() async throws {
        let app = try await editing()
        let before = app.editor.graph.nodes[fixture.rectangle.id]?.position
        app.window.typeText("XY")
        app.window.typeKey(.delete)
        app.window.typeKey(.leftArrow)
        app.window.typeText("Q")
        #expect(app.editor.commentEdit?.draft.hasSuffix("QX") == true, "Delete removed the Y and the arrow moved the caret")
        #expect(app.editor.graph.nodes[fixture.rectangle.id]?.position == before)
        #expect(app.editor.graph.nodes[fixture.rectangle.id] != nil, "Delete deleted no node")
    }

    @Test func spaceAndFAreTypedAndOpenNothing() async throws {
        let app = try await editing()
        app.window.typeText(" f")
        #expect(app.editor.commentEdit?.draft.hasSuffix(" f") == true)
        #expect(app.editor.palette == nil, "Space does not open the add-node palette")
    }

    @Test func commandChordsActOnTheTextNotTheCanvas() async throws {
        let app = try await editing()
        let notes = app.editor.graph.stickies.count
        let nodes = app.editor.graph.nodes.count
        app.window.typeKey("n", modifierFlags: [.primary, .shift])
        app.window.typeKey("c", modifierFlags: [.primary, .shift])
        app.window.typeKey("g", modifierFlags: .primary)
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.stickies.count == notes && app.editor.graph.frames.count == 1, "no note, no frame")
        #expect(app.editor.graph.nodes.count == nodes, "no group, no duplicate")
        #expect(app.editor.commentEdit?.id == fixture.note.id, "and the edit is still open")
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText("All new")
        #expect(app.editor.commentEdit?.draft == "All new", "⌘A selected the text, which typing replaced")
    }

    @Test func tabOpensNoPalette() async throws {
        let app = try await editing()
        app.window.typeKey(.tab)
        #expect(app.editor.palette == nil)
    }

    @Test func afterwardsTheGraphsKeysActOverTheCanvasButNotOverTheViewport() async throws {
        let app = try await editing()
        app.window.typeKey(.escape)
        let canvasSpot = app.point(inCanvasView: Vector2(900, 120))
        app.window.click(at: app.point(inCanvas: Vector2(620, 60) + Vector2(20, 40)))
        #expect(app.editor.selection == [fixture.rectangle.id])
        // The pointer over the viewport, above the panel: Delete does nothing to the selected node (User decision 1).
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey(.delete)
        #expect(app.editor.graph.nodes[fixture.rectangle.id] != nil)
        // The pointer back over the canvas, nothing focused: Delete deletes the node.
        app.window.hover(at: canvasSpot)
        app.window.typeKey(.delete)
        #expect(app.editor.graph.nodes[fixture.rectangle.id] == nil)
    }
}
