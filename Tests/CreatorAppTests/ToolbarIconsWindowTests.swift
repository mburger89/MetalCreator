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

    @Test func theLibraryButtonTogglesTheLibrary() async throws {
        let app = try await AppWindow.open(dock: .left)
        let shown = app.editor.showsLibrary
        try app.window.click(try app.window.element(label: HeaderText.libraryName))
        try await app.window.runUntilIdle()
        #expect(app.editor.showsLibrary == !shown)
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
        _ = try app.window.element(label: HeaderText.hideName)
        _ = try app.window.element(label: "Home view")
        _ = try app.window.element(label: "View options")
    }

    // MARK: Hit boxes

    /// The icon buttons are 24 x 24 whatever their glyph: a press in the corner of the box, 4 points beyond the glyph's own
    /// rectangle (Undo's is 16 x 14), still reaches the button and not the viewport under the bar.
    @Test func aPressNearTheUndoGlyphButInsideItsBoxUndoesAndDoesNotReachTheViewport() async throws {
        let app = try await AppWindow.open()
        let probe = ModifierProbeTool()
        app.model.viewport.tool = probe
        app.editor.addNote(atScreen: Vector2(30, 40))
        try await app.window.runUntilIdle()
        let undo = try app.window.element(label: app.model.undoTitle)
        #expect(undo.frame.size.width.value == 24 && undo.frame.size.height.value == 24)
        let x = undo.frame.origin.x.value + 2
        let y = undo.frame.origin.y.value + 2
        app.window.click(at: app.point(x, y))
        try await app.window.runUntilIdle()
        #expect(!app.model.document.canUndo, "the press undid the step")
        #expect(probe.clicks.isEmpty, "and did not reach the viewport")
    }

    @Test func aPressInTheCornerOfTheHomeBoxGoesHomeAndNotToTheViewport() async throws {
        let app = try await AppWindow.open(dock: .left)
        let probe = ModifierProbeTool()
        app.model.viewport.tool = probe
        let home = try app.window.element(label: "Home view")
        #expect(home.frame.size.width.value == 24 && home.frame.size.height.value == 24)
        app.window.click(at: app.point(home.frame.origin.x.value + 2, home.frame.origin.y.value + 2))
        try await app.window.runUntilIdle()
        #expect(probe.clicks.isEmpty, "the press stayed on the button")
        app.window.click(at: app.point(home.frame.origin.x.value + 2, home.frame.origin.y.value + 40))
        #expect(probe.clicks.count == 1, "while a press well below the box is the viewport's")
    }
}
