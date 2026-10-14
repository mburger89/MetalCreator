import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The menu bar's shortcuts are spelled with MetalUI's `.primary` modifier (cross-platform spec 2.4): ⌘ on macOS, where it is
/// value-identical to `.command`, and Ctrl on Linux and Windows.
@MainActor
struct AppShortcutTests {
    func shortcut(_ title: String, in menu: String, of app: AppWindow) throws -> PlatformKeyEquivalent? {
        let bar = try #require(app.testApp.menuBar.first { $0.title == menu })
        return try #require(bar.items.first { $0.title == title }).shortcut
    }

    @Test func theFileShortcutsUseThePrimaryModifier() async throws {
        let app = try await AppWindow.open()
        #expect(try shortcut("Save", in: "File", of: app) == PlatformKeyEquivalent(key: "s", modifiers: .primary))
        #expect(try shortcut("Save As…", in: "File", of: app) == PlatformKeyEquivalent(key: "s", modifiers: [.primary, .shift]))
        #expect(try shortcut("Export STL…", in: "File", of: app) == PlatformKeyEquivalent(key: "e", modifiers: [.primary, .shift]))
    }

    @Test func onMacOSThePrimaryModifierIsCommand() {
        #if os(macOS)
        #expect(Modifiers.primary == .command)
        #else
        #expect(Modifiers.primary == .control)
        #endif
    }
}
