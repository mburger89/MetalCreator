import Foundation
import Testing

/// The shader compiler is pinned once, in `scripts/shadercross.env`, and written again in the Dockerfile, the workflow and the
/// scripts' messages. This pins that they agree, and that the build script stops with a plain message, naming the tool and its pinned
/// commit, when it cannot find it. Read from the source tree (`#filePath`), so macOS runs them too.
struct ShaderToolchainTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// A text file of the repository with Windows line endings read as Unix ones (a CRLF checkout must not change the answer).
    static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }

    static func pin() throws -> (repository: String, commit: String) {
        let env = try text("scripts/shadercross.env")
        let commit = try #require(
            env.firstMatch(of: /(?m)^SHADERCROSS_COMMIT=([0-9a-f]{40})$/)?.1, "scripts/shadercross.env names a 40-digit commit")
        let repository = try #require(
            env.firstMatch(of: /(?m)^SHADERCROSS_REPOSITORY=(\S+)$/)?.1, "scripts/shadercross.env names the repository")
        return (String(repository), String(commit))
    }

    @Test func thePinIsWrittenOnceAndTheScriptsCompileThroughMetalUIsTool() throws {
        let pin = try Self.pin()
        #expect(pin.repository == "https://github.com/libsdl-org/SDL_shadercross")
        let dockerfile = try Self.text("scripts/linux/Dockerfile")
        let docker = try #require(
            dockerfile.firstMatch(of: /(?m)^ARG SHADERCROSS_COMMIT=([0-9a-f]{40})$/)?.1, "the Dockerfile's shadercross stage has the ARG")
        #expect(String(docker) == pin.commit, "scripts/linux/Dockerfile's SHADERCROSS_COMMIT differs from scripts/shadercross.env")
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("scripts/shadercross.env"),
                "the workflow keys the Windows cache on the env file, not on a copy of the commit")
        #expect(!workflow.contains("SHADERCROSS_COMMIT:"), "the workflow reads the pin from scripts/shadercross.env and does not repeat it")
        let ps = try Self.text("scripts/install-shadercross.ps1")
        #expect(ps.contains("shadercross.env"), "install-shadercross.ps1 reads the pin from the env file")
        // Both scripts compile through MetalUI's own tool (MetalUI S12, gap XP-G20), built with a scratch path outside ../MetalUI.
        for script in ["scripts/build-shaders.sh", "scripts/build-shaders.ps1"] {
            let text = try Self.text(script)
            #expect(text.contains("MetalUICompileShaders"), "\(script) runs MetalUI's MetalUICompileShaders")
            #expect(text.contains("--scratch-path"), "\(script) builds the tool outside ../MetalUI")
            #expect(!text.contains("compile-app-shaders.py"), "\(script) does not name MetalUI's deleted python script")
        }
    }

    /// The scripts' plain failure: no shadercross, exit 69, a line that names the tool, the repository and the pinned commit.
    #if !os(Windows)
    @Test func aMissingShadercrossStopsTheBuildNamingTheToolAndItsPin() throws {
        let pin = try Self.pin()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.root.appending(path: "scripts/build-shaders.sh").path]
        process.environment = ["SHADERCROSS": "/nonexistent/shadercross", "PATH": "/usr/bin:/bin"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let message = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 69)
        #expect(message.contains("SDL_shadercross"), "the message names the tool: \(message)")
        #expect(message.contains(pin.commit), "the message names the pinned commit: \(message)")
        #expect(message.contains("scripts/shadercross.env"), "the message says where the pin is written: \(message)")
    }
    #endif
}
