import Foundation
import Testing

#if !os(Windows)  // bash scripts: Windows has no /bin/bash
/// `packaging/linux/install.sh` registers an unpacked tarball with the desktop (gap XP-G5). Each test lays out a folder like the
/// tarball's (the script, the desktop entry, the MIME file and the icon), runs the script with `XDG_DATA_HOME` pointed at a scratch folder,
/// and reads what it wrote. The scratch folder's name has a space in it: a folder the person unpacked into "My Parts".
struct InstallScriptTests {
    /// What running the script did.
    struct Run {
        let status: Int32
        let data: URL
        let folder: URL
        var desktopEntry: String? { try? String(contentsOf: data.appending(path: "applications/\(Self.id).desktop"), encoding: .utf8) }
        var mimeFileExists: Bool { FileManager.default.fileExists(atPath: data.appending(path: "mime/packages/\(Self.id).xml").path) }
        var iconExists: Bool {
            FileManager.default.fileExists(atPath: data.appending(path: "icons/hicolor/256x256/apps/\(Self.id).png").path)
        }
        static let id = "com.metalcreator.MetalCreator"
    }

    @Test func theEntryIsInstalledWithTheFoldersOwnQuotedPath() throws {
        let run = try Self.run([], folderName: "My Parts")
        defer { try? FileManager.default.removeItem(at: run.folder.deletingLastPathComponent()) }
        #expect(run.status == 0)
        let entry = try #require(run.desktopEntry)
        // The script writes the physical path (`pwd -P`), which on a Mac differs from the temporary folder's spelling.
        #expect(entry.contains("\nExec=\"/") && entry.contains("/My Parts/MetalCreator\" %F\n"), "an absolute path, quoted, and %F kept")
        #expect(entry.contains("MimeType=application/x-metalcreator-graph;\n"))
        #expect(run.mimeFileExists)
        #expect(entry.contains("\nIcon=com.metalcreator.MetalCreator\n") && run.iconExists,
                "the icon the entry names is installed in hicolor")
    }

    /// Review focus: in a quoted Exec argument a percent sign starts a field code, so the path's own one is written `%%`.
    @Test func aPercentSignInTheFoldersNameIsWrittenDoubled() throws {
        let run = try Self.run([], folderName: "100% parts")
        defer { try? FileManager.default.removeItem(at: run.folder.deletingLastPathComponent()) }
        #expect(run.status == 0)
        let entry = try #require(run.desktopEntry)
        #expect(entry.contains("/100%% parts/MetalCreator\" %F\n"), "%% in the path, the real %F kept")
    }

    @Test func removeTakesTheInstalledFilesAway() throws {
        let installed = try Self.run([], folderName: "Parts")
        defer { try? FileManager.default.removeItem(at: installed.folder.deletingLastPathComponent()) }
        #expect(installed.desktopEntry != nil && installed.mimeFileExists && installed.iconExists)
        let removed = try Self.run(["--remove"], reusing: installed)
        #expect(removed.status == 0)
        #expect(removed.desktopEntry == nil && !removed.mimeFileExists && !removed.iconExists)
    }

    /// Review focus: a folder whose name an Exec line can't hold is refused, not written as a broken entry.
    @Test(arguments: ["a$b", "a&b", "a|b", "a`b"])
    func aFolderNameTheEntryCannotHoldIsRefused(_ name: String) throws {
        let run = try Self.run([], folderName: name)
        defer { try? FileManager.default.removeItem(at: run.folder.deletingLastPathComponent()) }
        #expect(run.status == 1)
        #expect(run.desktopEntry == nil)
    }

    // MARK: Fixture

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Lays out `<scratch>/<folderName>/` like the tarball and runs `install.sh arguments` from it.
    private static func run(_ arguments: [String], folderName: String) throws -> Run {
        let scratch = URL.temporaryDirectory.appending(path: "install-script-\(UUID().uuidString)")
        let folder = scratch.appending(path: folderName)
        let fileManager = FileManager.default
        for directory in ["share/applications", "share/mime/packages", "share/icons/hicolor/256x256/apps"] {
            try fileManager.createDirectory(at: folder.appending(path: directory), withIntermediateDirectories: true)
        }
        let id = Run.id
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/install.sh"), to: folder.appending(path: "install.sh"))
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/\(id).desktop"),
                                 to: folder.appending(path: "share/applications/\(id).desktop"))
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/\(id).xml"),
                                 to: folder.appending(path: "share/mime/packages/\(id).xml"))
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/\(id).png"),
                                 to: folder.appending(path: "share/icons/hicolor/256x256/apps/\(id).png"))
        return try run(arguments, reusing: Run(status: 0, data: scratch.appending(path: "data"), folder: folder))
    }

    private static func run(_ arguments: [String], reusing previous: Run) throws -> Run {
        let bash = Process()
        bash.executableURL = URL(filePath: "/bin/bash")
        bash.arguments = [previous.folder.appending(path: "install.sh").path] + arguments
        bash.environment = ["XDG_DATA_HOME": previous.data.path, "PATH": "/usr/bin:/bin", "HOME": previous.data.path]
        bash.standardOutput = FileHandle.nullDevice
        bash.standardError = FileHandle.nullDevice
        try bash.run()
        bash.waitUntilExit()
        return Run(status: bash.terminationStatus, data: previous.data, folder: previous.folder)
    }
}
#endif
