import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// Linux and Windows open `.mcgraph` files through the files in `packaging/` (cross-platform spec section 5, gap XP-G5): the
/// desktop entry runs `MetalCreator %F` and names the MIME type, the shared-mime-info file maps `*.mcgraph` to it, and the
/// Windows script registers the same extension. They are text, so these tests hold them to the names the app itself declares
/// (`AppBundleInfo`, `ContentType.mcgraph`); what a desktop then does with them is human checks XP-16, XP-17 and XP-19.
struct DesktopEntryTests {
    @Test func theEntryHandsTheFileManagersFilesToTheAppAndNamesTheType() throws {
        let entry = try Self.desktopEntry()
        #expect(entry["Type"] == "Application")
        #expect(entry["Name"] == AppBundleInfo.name)
        #expect(entry["Exec"] == "\(AppBundleInfo.executableName) %F", "%F: every selected file, as local paths")
        #expect(entry["MimeType"] == "\(AppBundleInfo.mimeType);")
        #expect(entry["StartupWMClass"] == AppBundleInfo.identifier)
        #expect(entry["Icon"] == AppBundleInfo.identifier, "an icon theme name: the file in hicolor is named after it")
        #expect(entry["Terminal"] == "false")
    }

    /// XP-G13, fixed in MetalUI master `b39d68d6`: MetalUI hands SDL the id `launchingSingleInstance(id:)` is given as the
    /// `SDL_APP_ID` hint, so the window's Wayland `app_id` / X11 `WM_CLASS` is `AppBundleInfo.identifier` with no code of ours. The
    /// entry's `StartupWMClass` must be that id, and nothing may override or work around it (an `applicationID:` option, a `setenv`,
    /// an `env SDL_APP_ID=` in the entry). A desktop shell showing the right icon and grouping is human check XP-16.
    @Test func theWindowClassIsTheApplicationIDTheAppHandsToMetalUI() throws {
        let entry = try Self.desktopEntry()
        #expect(entry["StartupWMClass"] == AppBundleInfo.identifier)
        #expect(AppBundleInfo.identifier == "com.metalcreator.MetalCreator",
                "the entry is named after it: com.metalcreator.MetalCreator.desktop")
        let main = try Self.text("Sources/MetalCreatorApp/main.swift")
        #expect(main.contains("launchingSingleInstance(id: AppBundleInfo.identifier"), "the id MetalUI turns into SDL_APP_ID")
        #expect(!main.contains("applicationID:") && !main.contains("SDL_APP_ID") && !main.contains("setenv"), "no override, no workaround")
        #expect(!(entry["Exec"] ?? "").contains("SDL_APP_ID"))
    }

    /// The icon the entry names is a file of the repository: a 256 x 256 PNG, which the tarball puts in hicolor's `256x256/apps` and
    /// the AppImage at its root.
    @Test func theIconIsA256PixelPNGNamedAfterTheEntry() throws {
        let bytes = try Self.bytes("packaging/linux/\(AppBundleInfo.identifier).png")
        #expect(Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
                "a PNG (and not rewritten by a line-ending rule)")
        func bigEndian(_ range: Range<Int>) -> Int { bytes[range].reduce(0) { $0 << 8 | Int($1) } }
        #expect(bigEndian(16..<20) == 256 && bigEndian(20..<24) == 256, "IHDR: width and height")
    }

    @Test func theMimeTypeGlobsTheDocumentExtensionTheFilePanelsUse() throws {
        let xml = try Self.text("packaging/linux/\(AppBundleInfo.identifier).xml")
        let ext = try #require(ContentType.mcgraph.preferredFilenameExtension)
        #expect(xml.contains(#"<mime-type type="\#(AppBundleInfo.mimeType)">"#))
        #expect(xml.contains(#"<glob pattern="*.\#(ext)"/>"#))
        #expect(xml.contains("<comment>\(AppBundleInfo.documentTypeName)</comment>"))
        #expect(xml.contains(#"<sub-class-of type="application/json"/>"#), "the document is JSON, as its macOS type says")
    }

    @Test func theWindowsScriptRegistersTheSameExtensionAndPassesTheFileAsTheArgument() throws {
        let script = try Self.text("packaging/windows/register-mcgraph.ps1")
        let ext = try #require(ContentType.mcgraph.preferredFilenameExtension)
        #expect(script.contains("\\.\(ext)"))
        #expect(script.contains(#""`"$exe`" `"%1`"""#), "shell\\open\\command is \"MetalCreator.exe\" \"%1\"")
        #expect(script.contains("MetalCreator.exe"))
    }

    /// A stock Windows 11 refuses to run a downloaded .ps1, so the zip ships a .cmd that runs it with the policy bypassed, passes
    /// `-Remove` through, exits with PowerShell's code, and `package-windows.ps1` puts it beside the .ps1.
    @Test func theWindowsCmdWrapperRunsTheScriptPastTheExecutionPolicyAndTheZipCarriesIt() throws {
        let wrapper = try Self.text("packaging/windows/register-mcgraph.cmd")
        #expect(wrapper.contains(#"powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0register-mcgraph.ps1" %*"#))
        #expect(wrapper.contains("exit /b %ERRORLEVEL%"), "PowerShell's exit code is the wrapper's")
        let packager = try Self.text("scripts/package-windows.ps1")
        #expect(packager.contains(#"packaging\windows\register-mcgraph.cmd') $folder"#), "the zip carries the .cmd beside the .ps1")
        #expect(packager.contains(#"packaging\windows\register-mcgraph.ps1') $folder"#))
        let attributes = try Self.text(".gitattributes")
        #expect(attributes.contains("\npackaging/windows/*.cmd text eol=crlf\n"), "cmd.exe scripts are checked out with CRLF")
    }

    /// A file of the repository as bytes.
    private static func bytes(_ path: String) throws -> [UInt8] {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [UInt8](try Data(contentsOf: repository.appending(path: path)))
    }

    /// The entry's `[Desktop Entry]` group as key-value pairs.
    private static func desktopEntry() throws -> [String: String] {
        let text = try Self.text("packaging/linux/\(AppBundleInfo.identifier).desktop")
        var pairs: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("[") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { pairs[String(parts[0])] = String(parts[1]) }
        }
        return pairs
    }

    /// A file of the repository as text (`Tests/CreatorAppTests/DesktopEntryTests.swift` is three levels down), with "\r\n" read as
    /// "\n": Swift counts "\r\n" as one Character, so a Windows checkout with CRLF would never split into lines.
    private static func text(_ path: String) throws -> String {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }
}
