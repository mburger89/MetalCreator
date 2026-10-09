import CreatorStyle
import Foundation
import Testing

/// Import… and Export…: `.mctheme` files anywhere on disk. An import is always a new custom theme.
@MainActor
struct ThemeImportExportTests {
    /// A path in the temporary directory; the caller removes it.
    static func temporaryFile(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
    }

    @Test func anExportedThemeImportsAsANewThemeWithAFreeName() throws {
        let url = Self.temporaryFile("Dracula.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ThemeStore()
        try store.exportTheme("dracula", to: url)
        let imported = try store.importTheme(from: url)
        #expect(imported.name == "Dracula 2", "never replaces a theme, built-in or custom")
        #expect(imported.colors == ColorTheme.dracula.colors.quantized && imported.isDark)
        #expect(store.current == imported && store.customs == [imported])
        #expect(try store.importTheme(from: url).name == "Dracula 3")
    }

    @Test func aCustomThemeExportsAsItIs() throws {
        let url = Self.temporaryFile("mine.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ThemeStore()
        let copy = try store.duplicate("nord")
        try store.rename(copy.id, to: "Fjord")
        try store.exportTheme(copy.id, to: url)
        let other = ThemeStore()
        let imported = try other.importTheme(from: url)
        #expect(imported.name == "Fjord" && imported.colors == store.current.colors)
    }

    @Test func aFileWithoutANameIsNamedAfterTheFile() throws {
        let url = Self.temporaryFile("Ocean.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{ "version": 1, "colors": {} }"#.utf8).write(to: url)
        #expect(try ThemeStore().importTheme(from: url).name == url.deletingPathExtension().lastPathComponent)
    }

    @Test func aBadFileIsRefusedPlainlyAndChangesNothing() throws {
        let url = Self.temporaryFile("bad.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{ "version": 1, "colors": { "selection": "pink" } }"#.utf8).write(to: url)
        let store = ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "nord"))
        #expect(throws: ThemeProblem("“\(url.lastPathComponent)” couldn’t be imported. ‘selection’ isn’t a colour like #ff79c6.")) {
            try store.importTheme(from: url)
        }
        #expect(store.customs.isEmpty && store.current == .nord)
    }

    @Test func aMissingFileIsRefused() {
        let url = Self.temporaryFile("gone.mctheme")
        let error = #expect(throws: ThemeProblem.self) { try ThemeStore().importTheme(from: url) }
        #expect(error?.message.hasPrefix("“\(url.lastPathComponent)” couldn’t be imported. ") == true)
    }

    @Test func anImportIsSavedInTheFolder() throws {
        let url = Self.temporaryFile("Nord.mctheme")
        let folder = ThemeFolderTests.temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: folder.url)
        }
        let store = ThemeStore(folder: folder)
        try store.exportTheme("nord", to: url)
        let imported = try store.importTheme(from: url)
        #expect(ThemeStore(folder: folder).customs == [imported])
    }

    /// A file that names only some roles: the missing ones are Dracula's, quantized, so the theme the import shows is
    /// the one the folder gives back at the next launch (Dracula's glass is 0.86 opaque, a file's 219/255).
    @Test func aPartialFileImportsAsTheThemeTheFolderReadsBack() throws {
        let url = Self.temporaryFile("Partial.mctheme")
        let folder = ThemeFolderTests.temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: folder.url)
        }
        try Data(#"{ "version": 1, "colors": {} }"#.utf8).write(to: url)
        let imported = try ThemeStore(folder: folder).importTheme(from: url)
        #expect(imported.colors == ColorTheme.dracula.colors.quantized)
        #expect(ThemeStore(folder: folder).customs == [imported])
    }
}
