import Foundation
import Testing

/// The packaging scripts parse and are executable. What they build is checked by running them: `scripts/verify-app.sh`
/// (which `scripts/package-app.sh` ends with) and human check P1.
struct PackagingScriptTests {
    @Test(arguments: ["package-app.sh", "verify-app.sh"])
    func theScriptParsesAndIsExecutable(_ name: String) throws {
        let script = Self.scripts.appending(path: name)
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let bash = Process()
        bash.executableURL = URL(filePath: "/bin/bash")
        bash.arguments = ["-n", script.path]
        try bash.run()
        bash.waitUntilExit()
        #expect(bash.terminationStatus == 0, "bash -n \(name)")
    }

    /// `<repo>/scripts`, found from this file (`Tests/CreatorAppTests/PackagingScriptTests.swift`).
    private static let scripts = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts")
}
