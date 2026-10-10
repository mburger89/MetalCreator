import CreatorStyle
import Foundation
import Testing

/// The themes folder: one `<id>.mctheme` per custom theme, in a temporary folder here, never the person's own.
struct ThemeFolderTests {
    /// A folder path in the temporary directory that doesn't exist yet; the caller removes it.
    static func temporaryFolder() -> ThemeFolder {
        ThemeFolder(URL.temporaryDirectory.appending(path: "ThemeFolderTests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    static func custom(_ id: String, _ name: String) -> ColorTheme {
        ColorTheme(id: id, name: name, isDark: true, colors: ColorTheme.nord.colors.quantized)
    }

    @Test func theAppsFolderIsInApplicationSupport() {
        #expect(ThemeFolder.applicationSupport.url.path(percentEncoded: false).hasSuffix("Application Support/MetalCreator/Themes/"))
    }

    @Test func aFolderThatDoesntExistHoldsNoThemes() {
        let loaded = Self.temporaryFolder().load(reserved: [])
        #expect(loaded.themes.isEmpty && loaded.problems.isEmpty)
    }

    @Test func savedThemesLoadBackByFileName() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.custom("custom-b", "Beta"))
        try folder.save(Self.custom("custom-a", "Alpha"))
        #expect(FileManager.default.fileExists(atPath: folder.fileURL(for: "custom-a").path(percentEncoded: false)))
        let loaded = folder.load(reserved: [])
        #expect(loaded.themes == [Self.custom("custom-a", "Alpha"), Self.custom("custom-b", "Beta")])
        #expect(loaded.problems.isEmpty)
    }

    @Test func removingDeletesTheFileAndAGoneFileIsFine() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.custom("custom-a", "Alpha"))
        try folder.remove("custom-a")
        #expect(folder.load(reserved: []).themes.isEmpty)
        try folder.remove("custom-a")
    }

    /// A damaged file, a bad colour or a file named like a built-in never stops the others loading, and each says
    /// why it was skipped. Other files are not themes and are left alone.
    @Test func unreadableFilesAreSkippedWithAReason() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.custom("custom-a", "Alpha"))
        try folder.save(Self.custom("dracula", "Not Dracula"))
        try Data("nope".utf8).write(to: folder.fileURL(for: "junk"))
        try Data(#"{ "version": 1, "colors": { "selection": "pink" } }"#.utf8).write(to: folder.fileURL(for: "pink"))
        try Data("notes".utf8).write(to: folder.url.appending(path: "notes.txt"))
        let loaded = folder.load(reserved: ["dracula"])
        #expect(loaded.themes == [Self.custom("custom-a", "Alpha")])
        #expect(loaded.problems == [
            "“dracula.mctheme” was skipped: its name is a built-in theme’s.",
            "“junk.mctheme” was skipped: It isn’t a MetalCreator theme, or it is damaged.",
            "“pink.mctheme” was skipped: ‘selection’ isn’t a colour like #ff79c6.",
        ])
    }

    @Test func aFileWithoutANameIsNamedByItsFile() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data(#"{ "version": 1, "colors": {} }"#.utf8).write(to: folder.fileURL(for: "Ocean"))
        #expect(folder.load(reserved: []).themes.map(\.name) == ["Ocean"])
    }

    @Test func aSaveThatFailsSaysSo() throws {
        let blocker = URL.temporaryDirectory.appending(path: "ThemeFolderTests-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("a file, not a folder".utf8).write(to: blocker)
        let error = #expect(throws: ThemeProblem.self) { try ThemeFolder(blocker).save(Self.custom("custom-a", "Alpha")) }
        #expect(error?.message.hasPrefix("“Alpha” couldn’t be saved: ") == true)
    }

    /// The usual volume is case-insensitive: "Dracula.mctheme" is the built-in's file name there, so it is skipped too.
    @Test func aFileNamedLikeABuiltInInAnotherCaseIsSkipped() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try ThemeFile.encode(Self.custom("Dracula", "Shouty")).write(to: folder.fileURL(for: "Dracula"))
        let loaded = folder.load(reserved: ["dracula"])
        #expect(loaded.themes.isEmpty)
        #expect(loaded.problems == ["“Dracula.mctheme” was skipped: its name is a built-in theme’s."])
    }

    @Test(arguments: ["a/b", "..", ".", ""])
    func anIdThatIsNotAFileNameIsNeverWrittenOrRemoved(_ id: String) {
        let folder = Self.temporaryFolder()
        #expect(throws: ThemeProblem.self) { try folder.save(Self.custom(id, "Odd")) }
        #expect(throws: ThemeProblem.self) { try folder.remove(id) }
        #expect(!FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)), "not even the folder")
    }
}
