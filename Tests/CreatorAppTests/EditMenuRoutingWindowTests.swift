import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The Edit menu and the chords that run before the graph's keys (human check M6-5; "menu commands running before
/// `onInput`" in gap M6-e): the menu bar the app installs is read and run through MetalUITesting, and the chords go through
/// the real window's key routing.
@MainActor
struct EditMenuRoutingWindowTests {
    let fixture = TypingFixture()

    func editMenu(_ app: AppWindow) throws -> [PlatformMenuItem] {
        try #require(app.testApp.menuBar.first { $0.title == "Edit" }).items
    }

    /// The app after one committed note edit ("Edit Note"), the pointer over the canvas.
    func afterAnEdit() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("New ")
        app.window.typeKey(.return, modifierFlags: .primary)
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        return app
    }

    @Test func theEditMenuNamesTheStepAndRunsUndoAndRedo() async throws {
        let app = try await afterAnEdit()
        let titles = try editMenu(app).prefix(2).map(\.title)
        #expect(titles == ["Undo Edit Note", "Redo"])
        try app.testApp.performMenuBarItem("Edit", "Undo Edit Note")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(try editMenu(app).prefix(2).map(\.title) == ["Undo", "Redo Edit Note"])
        #expect(try editMenu(app).first?.isEnabled == false, "nothing left to undo")
        try app.testApp.performMenuBarItem("Edit", "Redo Edit Note")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one")
    }

    /// Over the canvas the graph's own ⌘Z answers, over the viewport the Edit menu's: the same step either way.
    @Test(arguments: [false, true])
    func commandZAndShiftCommandZUndoAndRedoOneStepEach(overTheViewport: Bool) async throws {
        let app = try await afterAnEdit()
        if overTheViewport { app.window.hover(at: Point(x: Pixels(700), y: Pixels(300))) }
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(!app.editor.document.canUndo && app.editor.document.canRedo)
        app.window.typeKey("z", modifierFlags: [.primary, .shift])
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one")
        #expect(app.editor.document.canUndo && !app.editor.document.canRedo)
    }

    @Test func copyPasteAndDuplicateChordsActOverTheCanvasAndNotOverTheViewport() async throws {
        var builder = GraphBuilder()
        let node = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [node.id])
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey("c", modifierFlags: .primary)
        app.window.typeKey("v", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 2, "⌘C then ⌘V pasted a copy; the standard items did not swallow the keys")
        #expect(app.editor.document.undoName == "Paste")
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 3)
        #expect(app.editor.document.undoName == "Duplicate")
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 3, "over the viewport the graph's chords do nothing")
    }
}
