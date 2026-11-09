import Foundation
import Testing

/// The packaging scripts parse and are executable. What they build is checked by running them: `scripts/verify-app.sh`
/// (which `scripts/package-app.sh` ends with), `scripts/linux-test.sh package` (the Linux tarball, run in a clean Ubuntu),
/// CI's Windows job (the zip, `scripts/package-windows.ps1`) and human checks P1, XP-16 and XP-17.
#if !os(Windows)  // bash scripts: Windows has no /bin/bash
struct PackagingScriptTests {
    @Test(arguments: [
        "scripts/package-app.sh", "scripts/verify-app.sh", "scripts/linux-test.sh", "scripts/package-linux.sh",
        "packaging/linux/install.sh", "scripts/package-appimage.sh", "packaging/appimage/AppRun",
    ])
    func theScriptParsesAndIsExecutable(_ name: String) throws {
        let script = Self.repository.appending(path: name)
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let bash = Process()
        bash.executableURL = URL(filePath: "/bin/bash")
        bash.arguments = ["-n", script.path]
        try bash.run()
        bash.waitUntilExit()
        #expect(bash.terminationStatus == 0, "bash -n \(name)")
    }

    /// MIT requires the notice in distributed copies: each package script copies the root `LICENSE` into the package as
    /// `MetalCreator-LICENSE.txt`, and the macOS verifier requires it. The AppImage is packed from the Linux tarball's tree.
    @Test(arguments: ["scripts/package-app.sh", "scripts/package-linux.sh", "scripts/package-windows.ps1"])
    func thePackageShipsMetalCreatorsLicense(_ name: String) throws {
        let text = try String(contentsOf: Self.repository.appending(path: name), encoding: .utf8)
        #expect(text.contains("MetalCreator-LICENSE.txt"), "\(name) must ship MetalCreator-LICENSE.txt")
        #expect(text.contains("\"$ROOT/LICENSE\"") || text.contains("Join-Path $root 'LICENSE'"), "\(name) must copy the root LICENSE")
        let verifier = try String(contentsOf: Self.repository.appending(path: "scripts/verify-app.sh"), encoding: .utf8)
        #expect(verifier.contains("MetalCreator/MetalCreator-LICENSE.txt"))
        #expect(text.contains("MetalUI-LICENSE.txt"), "\(name) must ship MetalUI-LICENSE.txt")
        #expect(verifier.contains("MetalUI/MetalUI-LICENSE.txt"))
    }

    /// The MCP bridge (`metalcreator-mcp`) ships beside the app's executable in every package, and the macOS verifier runs it.
    @Test(arguments: ["scripts/package-app.sh", "scripts/package-linux.sh", "scripts/package-windows.ps1", "scripts/verify-app.sh"])
    func thePackageShipsTheMCPBridge(_ name: String) throws {
        let text = try String(contentsOf: Self.repository.appending(path: name), encoding: .utf8)
        #expect(text.contains("metalcreator-mcp"), "\(name) must name metalcreator-mcp")
    }

    /// `<repo>`, found from this file (`Tests/CreatorAppTests/PackagingScriptTests.swift`).
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
#endif
