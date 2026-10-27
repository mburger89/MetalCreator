import CreatorEditor
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// Reduce Motion through a real headless window (cable ties spec 2026-10-26 §5.2): the canvas reads MetalUI's
/// `accessibilityReduceMotion` and passes it to the editor, which then never lets a wire go slack.
@MainActor
struct WireMotionWindowTests {
    @Test func theCanvasPassesReduceMotionToTheEditor() async throws {
        let app = try await AppWindow.open()
        #expect(!app.editor.reducesMotion)
        app.window.setReduceMotion(true)
        try await app.window.runUntilIdle()
        #expect(app.editor.reducesMotion)
        app.window.setReduceMotion(false)
        try await app.window.runUntilIdle()
        #expect(!app.editor.reducesMotion)
    }
}
