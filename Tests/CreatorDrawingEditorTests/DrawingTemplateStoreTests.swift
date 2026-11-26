import CreatorDrawing
import CreatorDrawingEditor
import Foundation
import Testing

/// DR-5 R10: the templates folder and the store over it, each test in a temporary folder of its own.
@MainActor
struct DrawingTemplateStoreTests {
    static func folder() -> DrawingTemplateFolder {
        let name = "DrawingTemplateStoreTests-\(UUID().uuidString)"
        return DrawingTemplateFolder(URL.temporaryDirectory.appending(path: name, directoryHint: .isDirectory))
    }

    static func template(_ name: String, id: String = UUID().uuidString) -> DrawingTemplate {
        .made(from: DrawingSheet(name: "S", titleBlock: TitleBlock(owner: "Acme")), standard: .iso, logo: nil, name: name, id: id)
    }

    static func files(in folder: DrawingTemplateFolder) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false))) ?? []).sorted()
    }

    static func sparse(_ url: URL, size: UInt64) throws {
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
        try handle.close()
    }

    @Test func aMemoryStoreSavesNothing() {
        let store = DrawingTemplateStore()
        let template = Self.template("Acme")
        store.add(template)
        store.rename(template.id, to: "Other")
        #expect(store.template(template.id)?.name == "Other")
        store.remove(template.id)
        #expect(store.templates.isEmpty && store.saveProblem == nil)
    }

    @Test func changesAreSavedAtOnce() {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = DrawingTemplateStore(folder: folder)
        let template = Self.template("Acme", id: "one")
        store.add(template)
        #expect(Self.files(in: folder) == ["one.mctemplate"])
        store.rename("one", to: "  Renamed  ")
        #expect(store.template("one")?.name == "Renamed")
        let reloaded = DrawingTemplateStore(folder: folder)
        #expect(reloaded.templates.map(\.name) == ["Renamed"])
        store.remove("one")
        #expect(Self.files(in: folder).isEmpty && store.templates.isEmpty)
    }

    @Test func templatesSortByName() {
        let store = DrawingTemplateStore()
        for name in ["b", "A", "c"] { store.add(Self.template(name)) }
        #expect(store.templates.map(\.name) == ["A", "b", "c"])
    }

    @Test func namesAreUnique() {
        let store = DrawingTemplateStore()
        store.add(Self.template("Acme"))
        store.add(Self.template("Acme"))
        store.add(Self.template("Acme"))
        #expect(store.templates.map(\.name) == ["Acme", "Acme 2", "Acme 3"])
        #expect(store.uniqueName("Acme") == "Acme 4")
        #expect(store.uniqueName("Fresh") == "Fresh")
    }

    @Test func aBlankNameIsRefused() {
        let store = DrawingTemplateStore()
        let template = Self.template("Acme")
        store.add(template)
        store.rename(template.id, to: "   ")
        #expect(store.template(template.id)?.name == "Acme")
        #expect(store.saveProblem == "A template needs a name.")
    }

    @Test func skippedFilesAreListed() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.template("Good", id: "good"))
        try Data("nonsense".utf8).write(to: folder.url.appending(path: "bad.mctemplate"))
        try Data("ignored".utf8).write(to: folder.url.appending(path: "notes.txt"))
        let store = DrawingTemplateStore(folder: folder)
        #expect(store.templates.map(\.id) == ["good"])
        #expect(store.loadProblems == ["“bad.mctemplate” was skipped: it isn't a drawing template."])
    }

    @Test func aHugeTemplateIsSkippedUnread() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.template("Good", id: "good"))
        try Self.sparse(folder.url.appending(path: "big.mctemplate"), size: 1_073_741_824)
        let loaded = folder.load()
        #expect(loaded.templates.map(\.id) == ["good"])
        #expect(loaded.problems == ["“big.mctemplate” was skipped: it is larger than 3 MB."])
    }

    @Test func aFolderNamedLikeATemplateIsSkipped() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url.appending(path: "dir.mctemplate"), withIntermediateDirectories: true)
        let loaded = folder.load()
        #expect(loaded.templates.isEmpty)
        #expect(loaded.problems == ["“dir.mctemplate” was skipped: it isn't a file."])
    }

    @Test func theStemIsTheID() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.template("Hand", id: "Seed"))
        let seed = folder.url.appending(path: "Seed.mctemplate")
        try FileManager.default.moveItem(at: seed, to: folder.url.appending(path: "X.mctemplate"))
        #expect(folder.load().templates.map(\.id) == ["X"])
        let uuid = UUID().uuidString
        let store = DrawingTemplateStore(folder: folder)
        store.add(Self.template("Acme", id: uuid))
        #expect(Self.files(in: folder).contains("\(uuid).mctemplate"))
        #expect(DrawingTemplateStore(folder: folder).template(uuid)?.name == "Acme")
    }

    @Test func anUnusableIDIsRefused() {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = DrawingTemplateStore(folder: folder)
        store.add(Self.template("Acme", id: "../a"))
        #expect(store.saveProblem == "“Acme” couldn't be saved: its id can't be a file name.")
        #expect(store.templates.isEmpty && Self.files(in: folder).isEmpty)
        #expect(!DrawingTemplateFolder.isUsable("") && !DrawingTemplateFolder.isUsable(".hidden"))
        #expect(!DrawingTemplateFolder.isUsable("a\\b"))
        #expect(!DrawingTemplateFolder.isUsable("a\u{7}b") && !DrawingTemplateFolder.isUsable(String(repeating: "a", count: 201)))
        #expect(DrawingTemplateFolder.isUsable(UUID().uuidString))
    }

    #if !os(Windows)
    /// A read-only folder only refuses a save to a user who obeys permissions: not root (a Linux container's user).
    private nonisolated static let permissionsApply = geteuid() != 0

    @Test(.enabled(if: Self.permissionsApply)) func aFailedSaveLeavesTheStore() throws {
        let folder = Self.folder()
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder.url)
        }
        let store = DrawingTemplateStore(folder: folder)
        store.add(Self.template("Keep", id: "keep"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path(percentEncoded: false))
        store.add(Self.template("Acme", id: "new"))
        #expect(store.saveProblem?.hasPrefix("“Acme” couldn't be saved: ") == true)
        #expect(store.templates.map(\.id) == ["keep"])
        store.remove("keep")
        #expect(store.saveProblem?.hasPrefix("“Keep” couldn't be deleted: ") == true)
        #expect(store.templates.map(\.id) == ["keep"])
    }
    #endif
}
