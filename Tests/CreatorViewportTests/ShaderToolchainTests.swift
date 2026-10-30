import Foundation
import Testing

/// The shader compiler is pinned once, in `scripts/shadercross.env`, and written again in the Dockerfile, the workflow and the
/// scripts' messages. This pins that they agree, and that the manifest applies MetalUI's shader plugin on Linux and Windows only and the
/// workflow and the Linux script hand it the shader compiler. Read from the source tree (`#filePath`), so macOS runs them too.
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

    @Test func thePinIsWrittenOnceAndThePluginCompilesWithIt() throws {
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
        // The viewport's shaders compile through MetalUI's build-tool plugin (BS-D), which the manifest applies on Linux and Windows only, so a
        // Mac build needs no shadercross. The scripts that ran MetalUI's tool by hand are gone.
        let manifest = try Self.text("Package.swift")
        #expect(manifest.contains("""
            #if os(Linux) || os(Windows)
            let shaderPlugins: [Target.PluginUsage] = [.plugin(name: "CompileShadersOnBuild", package: "MetalUI")]
            #else
            let shaderPlugins: [Target.PluginUsage] = []
            #endif
            """), "Package.swift applies CompileShadersOnBuild under `#if os(Linux) || os(Windows)` only")
        #expect(manifest.contains("plugins: shaderPlugins"), "CreatorViewport opts in")
        for gone in ["scripts/build-shaders.sh", "scripts/build-shaders.ps1"] {
            let exists = FileManager.default.fileExists(atPath: Self.root.appending(path: gone).path)
            #expect(!exists, "\(gone) is retired; the plugin does its work")
        }
    }

    /// The workflow's MetalUI checkout is the commit with the plugin (BS-D, XP-G32), and the Linux script hands the plugin the image's
    /// shadercross by `METALUI_SHADERCROSS`.
    @Test func theWorkflowAndTheLinuxScriptReachShadercrossForThePlugin() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("METALUI_COMMIT: cc8995d32aaee8eaa7471ffdd765f64f6ab4644b"))
        #expect(workflow.contains(#"METALUI_SHADERCROSS=$env:RUNNER_TEMP\shadercross\bin\shadercross.exe"#),
                "the Windows job names shadercross for the plugin")
        let script = try Self.text("scripts/linux-test.sh")
        #expect(script.contains("METALUI_SHADERCROSS=/opt/shadercross/bin/shadercross"), "the image's shadercross is the plugin's")
    }
}
