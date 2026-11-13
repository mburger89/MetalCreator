import CreatorEditor
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The icon buttons (toolbar-icons): the bundled glyphs carry no accessibility label, so each control passes its own, and
/// the app's real window finds them by it.
@MainActor
struct ToolbarIconsWindowTests {
    @Test func theTopBarIconsAreLabelledForAccessibility() async throws {
        let app = try await AppWindow.open()
        for label in ["Undo", "Redo", "Export"] {
            _ = try app.window.element(label: label)
        }
    }

    @Test func undoAndRedoFollowTheirStepTitles() async throws {
        let app = try await AppWindow.open()
        app.editor.addNote(atScreen: Vector2(30, 40))
        try await app.window.runUntilIdle()
        #expect(app.model.undoTitle == "Undo Add Note")
        _ = try app.window.element(label: app.model.undoTitle)
        app.model.undo()
        try await app.window.runUntilIdle()
        _ = try app.window.element(label: "Undo")
        _ = try app.window.element(label: app.model.redoTitle)
        #expect(app.model.redoTitle == "Redo Add Note")
    }

    @Test func theLibraryButtonFollowsShowsLibrary() async throws {
        let app = try await AppWindow.open(dock: .left)
        let shown = app.editor.showsLibrary
        let label = shown ? HeaderText.hideLibrary : HeaderText.showLibrary
        try app.window.click(try app.window.element(label: label))
        try await app.window.runUntilIdle()
        #expect(app.editor.showsLibrary == !shown)
        _ = try app.window.element(label: shown ? HeaderText.showLibrary : HeaderText.hideLibrary)
    }

    @Test func theDockPickerSwitchesTheDock() async throws {
        let app = try await AppWindow.open(dock: .left)
        try app.window.click(try app.window.element(label: HeaderText.dockBottomName))
        try await app.window.runUntilIdle()
        #expect(app.editor.dock == .bottom)
        try app.window.click(try app.window.element(label: HeaderText.dockLeftName))
        try await app.window.runUntilIdle()
        #expect(app.editor.dock == .left)
    }

    @Test func hideAndTheViewCubeIconsAreLabelled() async throws {
        let app = try await AppWindow.open(dock: .left)
        _ = try app.window.element(label: HeaderText.hide)
        _ = try app.window.element(label: "Home view")
        _ = try app.window.element(label: "View options")
    }
}
