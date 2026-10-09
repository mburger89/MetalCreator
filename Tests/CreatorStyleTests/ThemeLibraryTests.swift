import CreatorStyle
import Foundation
import Observation
import Testing

/// Custom themes: duplicate any theme, then rename, recolour, darken or delete the copy; the built-ins stay
/// read-only. With a folder every change is on disk at once; without one (most tests) it is kept in memory.
@MainActor
struct ThemeLibraryTests {
    static let readOnly = ThemeProblem("Built-in themes can’t be changed. Duplicate one to make your own.")

    /// Counts observation callbacks.
    @MainActor
    final class Observer {
        var changes = 0
    }

    @Test func duplicatingABuiltInMakesAnEditableCopyAndShowsIt() throws {
        let preferences = InMemoryThemePreferences()
        let store = ThemeStore(preferences: preferences)
        let copy = try store.duplicate("dracula")
        #expect(copy.name == "Dracula Copy" && copy.isDark)
        #expect(copy.colors == ColorTheme.dracula.colors.quantized)
        #expect(copy.id.hasPrefix("custom-"))
        #expect(store.customs == [copy] && store.current == copy && preferences.selectedThemeID == copy.id)
        #expect(!store.isBuiltIn(copy.id) && store.isBuiltIn("dracula"))
        #expect(store.themes.map(\.name) == ["Dracula", "Alucard", "Nord", "Dracula Copy"])
    }

    @Test func copiesAreNumberedAndListedByName() throws {
        let store = ThemeStore()
        let first = try store.duplicate("nord")
        try store.duplicate("nord")
        try store.duplicate(first.id)
        try store.duplicate("alucard")
        #expect(store.customs.map(\.name) == ["Alucard Copy", "Nord Copy", "Nord Copy 2", "Nord Copy Copy"])
    }

    @Test func theBuiltInsAreReadOnly() throws {
        let store = ThemeStore()
        let accent = try #require(ThemeRole.named("accent"))
        #expect(throws: Self.readOnly) { try store.rename("dracula", to: "Mine") }
        #expect(throws: Self.readOnly) { try store.setColor(HexColor(0x000000), for: accent, in: "nord") }
        #expect(throws: Self.readOnly) { try store.setDark(false, in: "dracula") }
        #expect(throws: Self.readOnly) { try store.delete("alucard") }
        #expect(store.builtIns == ColorTheme.builtIns && store.customs.isEmpty)
        #expect(throws: ThemeProblem("That theme no longer exists.")) { try store.rename("custom-gone", to: "Mine") }
    }

    @Test func renamingTrimsAndRefusesEmptyAndTakenNames() throws {
        let store = ThemeStore()
        let copy = try store.duplicate("dracula")
        try store.rename(copy.id, to: "  Midnight ")
        #expect(store.current.name == "Midnight" && store.customs.map(\.name) == ["Midnight"])
        #expect(throws: ThemeProblem("A theme needs a name.")) { try store.rename(copy.id, to: "   ") }
        #expect(throws: ThemeProblem("There’s already a theme called “nord”.")) { try store.rename(copy.id, to: "nord") }
        try store.rename(copy.id, to: "MIDNIGHT")
        #expect(store.current.name == "MIDNIGHT", "a change of case alone is its own name")
        #expect(store.current.id == copy.id)
    }

    @Test func renamingReordersTheList() throws {
        let store = ThemeStore()
        let first = try store.duplicate("dracula")
        try store.duplicate("nord")
        try store.rename(first.id, to: "Zebra")
        #expect(store.customs.map(\.name) == ["Nord Copy", "Zebra"])
    }

    @Test func aColourEditIsShownAtOnce() throws {
        let store = ThemeStore()
        let copy = try store.duplicate("dracula")
        let observer = Observer()
        withObservationTracking { _ = store.current } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        let selection = try #require(ThemeRole.named("selection"))
        try store.setColor(HexColor(0x00ffaa), for: selection, in: copy.id)
        #expect(store.current.colors.selection == HexColor(0x00ffaa))
        #expect(observer.changes == 1, "the views and the viewport redraw")
        try store.setColor(HexColor(0x101010, opacity: 0.5), for: try #require(ThemeRole.named("glassFill")), in: copy.id)
        #expect(store.current.colors.glassFill == HexColor(0x101010, opacity: 128.0 / 255), "quantized as the file holds it")
        #expect(ThemeStore().current.colors.selection == HexColor(0xff79c6), "Dracula itself is untouched")
    }

    @Test func darkCanBeTurnedOff() throws {
        let store = ThemeStore()
        let copy = try store.duplicate("dracula")
        try store.setDark(false, in: copy.id)
        #expect(!store.current.isDark)
    }

    @Test func deletingTheShownThemeShowsDracula() throws {
        let preferences = InMemoryThemePreferences()
        let store = ThemeStore(preferences: preferences)
        let copy = try store.duplicate("nord")
        let other = try store.duplicate("alucard")
        try store.delete(other.id)
        #expect(store.customs == [copy])
        #expect(store.current == .dracula && preferences.selectedThemeID == "dracula")
    }

    @Test func aFolderKeepsEveryChange() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        try store.rename(copy.id, to: "Midnight")
        try store.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("accent")), in: copy.id)
        try store.setDark(false, in: copy.id)
        let doomed = try store.duplicate("nord")
        #expect(ThemeStore(folder: folder).customs == store.customs)
        try store.delete(doomed.id)
        let reloaded = ThemeStore(folder: folder)
        #expect(reloaded.customs == store.customs && reloaded.customs.count == 1)
        #expect(reloaded.customs.first?.colors.accent == HexColor(0x00ffaa))
    }

    /// Review focus: a colour drag writes on every move; the last colour is the one kept.
    @Test func manyQuickEditsKeepTheLastColour() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let accent = try #require(ThemeRole.named("accent"))
        for step in 0..<120 {
            try store.setColor(HexColor(UInt32(step) << 16), for: accent, in: copy.id)
        }
        #expect(ThemeStore(folder: folder).customs.first?.colors.accent == HexColor(119 << 16))
    }

    /// Review focus: the remembered theme is a custom one, or one that has since gone.
    @Test func theRememberedCustomThemeIsShownAtLaunchAndAGoneOneFallsBackToDracula() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let preferences = InMemoryThemePreferences()
        let copy = try ThemeStore(preferences: preferences, folder: folder).duplicate("nord")
        #expect(ThemeStore(preferences: preferences, folder: folder).current == copy)
        try FileManager.default.removeItem(at: folder.fileURL(for: copy.id))
        #expect(ThemeStore(preferences: preferences, folder: folder).current == .dracula)
    }

    /// Review focus: an unreadable file in the folder never stops the app starting; the editor shows why.
    @Test func filesThatCantBeReadAreReported() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.fileURL(for: "junk"))
        let store = ThemeStore(folder: folder)
        #expect(store.customs.isEmpty && store.current == .dracula)
        #expect(store.loadProblems == ["“junk.mctheme” was skipped: It isn’t a MetalCreator theme, or it is damaged."])
    }

    /// Review focus: a save that fails (a full disk, a locked folder) changes nothing and says why.
    @Test func aFailedSaveChangesNothing() throws {
        let blocker = URL.temporaryDirectory.appending(path: "ThemeLibraryTests-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("a file, not a folder".utf8).write(to: blocker)
        let preferences = InMemoryThemePreferences(selectedThemeID: "nord")
        let store = ThemeStore(preferences: preferences, folder: ThemeFolder(blocker))
        let error = #expect(throws: ThemeProblem.self) { try store.duplicate("dracula") }
        #expect(error?.message.hasPrefix("“Dracula Copy” couldn’t be saved: ") == true)
        #expect(store.customs.isEmpty && store.current == .nord && preferences.selectedThemeID == "nord")
    }
}
