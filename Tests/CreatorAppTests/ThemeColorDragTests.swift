import CreatorStyle
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// A colour picker's drag in the theme editor: every sample is shown at once, and the theme's file is written once,
/// when the drag pauses, the editor closes or the window is asked to close.
@MainActor
struct ThemeColorDragTests {
    /// Stands in for `ThemeEditorModel.saveDelay`: a sleep that lasts until the test opens the gate.
    @MainActor
    final class Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { waiting.append($0) }
        }

        /// Lets the sleeps asked for begin, ends them all, and lets the tasks they wake run.
        func open() async {
            for _ in 0..<20 { await Task.yield() }
            let released = waiting
            waiting = []
            for continuation in released { continuation.resume() }
            for _ in 0..<20 { await Task.yield() }
        }
    }

    let accent = ThemeRole.named("accent")

    /// An editor on a custom copy of Dracula saved in a temporary folder, and the gate its save delay waits on.
    func makeEditor() throws -> (editor: ThemeEditorModel, folder: ThemeFolder, gate: Gate) {
        let folder = ThemeFolder(URL.temporaryDirectory.appending(path: "ThemeColorDragTests-\(UUID().uuidString)",
                                                  directoryHint: .isDirectory))
        let gate = Gate()
        let editor = ThemeEditorModel(themes: ThemeStore(folder: folder), sleep: { _ in await gate.wait() })
        editor.duplicate()
        try #require(editor.isEditable)
        return (editor, folder, gate)
    }

    func savedAccent(_ folder: ThemeFolder) -> HexColor? {
        folder.load(reserved: []).themes.first?.colors.accent
    }

    @Test func aDragShowsEverySampleAndWritesOnceWhenItPauses() async throws {
        let (editor, folder, gate) = try makeEditor()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let role = try #require(accent)
        let before = try #require(savedAccent(folder))
        let binding = editor.colorBinding(for: role)
        for step in 1...50 {
            binding.wrappedValue = Color(.sRGB, red: Double(step) / 255, green: 0, blue: 0)
            #expect(editor.theme.colors.accent == HexColor(UInt32(step) << 16), "shown at once")
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(savedAccent(folder) == before, "no write while the drag goes on")
        await gate.open()
        #expect(savedAccent(folder) == HexColor(50 << 16), "the last sample, written when the drag paused")
        #expect(!editor.themes.hasUnsavedColors && editor.message == nil)
    }

    @Test func closingTheEditorSavesAtOnce() async throws {
        let (editor, folder, _) = try makeEditor()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        editor.dragColor(HexColor(0x123456), for: try #require(accent))
        #expect(savedAccent(folder) != HexColor(0x123456))
        editor.close()
        #expect(savedAccent(folder) == HexColor(0x123456))
    }

    @Test func flushSavesAtOnceAndTheLaterWakeDoesNothing() async throws {
        let (editor, folder, gate) = try makeEditor()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        editor.dragColor(HexColor(0x654321), for: try #require(accent))
        editor.flush()
        #expect(savedAccent(folder) == HexColor(0x654321))
        await gate.open()
        #expect(savedAccent(folder) == HexColor(0x654321) && editor.message == nil)
    }

    @Test func aFailedSaveShowsTheSavedColourAgainAndSaysWhy() async throws {
        let (editor, folder, gate) = try makeEditor()
        let role = try #require(accent)
        let saved = try #require(savedAccent(folder))
        editor.dragColor(HexColor(0x123456), for: role)
        try FileManager.default.removeItem(at: folder.url)
        try Data("in the way".utf8).write(to: folder.url)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        await gate.open()
        #expect(editor.theme.colors.accent == saved)
        #expect(editor.message?.contains("couldn’t be saved") == true)
    }

    @Test func aBuiltInThemeStaysUntouchedAndSaysSo() throws {
        let editor = ThemeEditorModel(themes: ThemeStore())
        editor.dragColor(HexColor(0), for: try #require(accent))
        #expect(editor.theme == .dracula)
        #expect(editor.message == "Built-in themes can’t be changed. Duplicate one to make your own.")
    }
}
