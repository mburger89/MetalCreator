import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

extension AppWindow {
    /// Opens the top bar's Analysis menu and returns its items.
    func openAnalysisMenu() throws -> [PlatformMenuItem] {
        try window.click(try window.element(label: "Analysis"))
        let menu = try #require(window.presentedMenu, "the Analysis menu did not open")
        return menu.items
    }

    /// Chooses `title` in the top bar's Analysis menu, then settles.
    func chooseAnalysis(_ title: String) async throws {
        _ = try openAnalysisMenu()
        try window.chooseMenuItem(title)
        try await window.runUntilIdle()
    }
}
