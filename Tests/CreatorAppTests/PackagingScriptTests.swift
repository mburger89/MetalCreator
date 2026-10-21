import Foundation
import Testing

/// The packaging scripts parse and are executable. What they build is checked by running them: `scripts/verify-app.sh`
/// (which `scripts/package-app.sh` ends with), `scripts/linux-test.sh package` (the Linux tarball, run in a clean Ubuntu),
/// CI's Windows job (the zip, `scripts/package-windows.ps1`) and human checks P1, XP-16 and XP-17.
#if !os(Windows)  // bash scripts: Windows has no /bin/bash
struct PackagingScriptTests {
    @Test(arguments: ["scripts/package-app.sh", "scripts/verify-app.sh", "scripts/linux-test.sh"])
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

    /// `<repo>`, found from this file (`Tests/CreatorAppTests/PackagingScriptTests.swift`).
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
#endif
