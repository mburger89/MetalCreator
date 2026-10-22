import Foundation
import Testing

/// Numbers and hashes that are written in more than one file must agree (cross-platform spec section 2.5, 2.6; plan xp-2).
/// A change to one place that misses another shows up here, not as a red CI run an hour later.
struct CIPinTests {
    /// The "Test run with" lines a full `swift test` prints on every platform since xp-2 put `CreatorOCCTTests` on Linux and
    /// Windows. A new test target raises it everywhere below.
    static let testRuns = 12

    @Test func theWindowsJobExpectsTheCount() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("EXPECTED_TEST_RUNS: \(Self.testRuns)\n"))
        #expect(!workflow.contains("EXPECTED_TEST_RUNS: 11"))
    }

    @Test func theLinuxScriptDefaultsToTheCount() throws {
        let script = try Self.text("scripts/linux-test.sh")
        #expect(script.contains("EXPECTED_TEST_RUNS=${EXPECTED_TEST_RUNS:-\(Self.testRuns)}"))
        #expect(!script.contains("EXPECTED_TEST_RUNS:-11"))
    }

    @Test func theProjectGuideStatesTheCountForEveryPlatform() throws {
        let guide = try Self.text("CLAUDE.md")
        #expect(guide.contains("exit 0 and \(Self.testRuns) \"Test run with\" lines"))
        #expect(!guide.contains("and 11 \"Test run with\""), "the Linux count is no longer eleven")
        #expect(!guide.contains("(11 \"Test run with\" lines)"), "the linux-test.sh line says twelve")
    }

    /// Review focus: the vcpkg manifest and the workflow name the same vcpkg commit, or the cache key and the build disagree.
    @Test func theWindowsManifestsBaselineIsTheWorkflowsVcpkgCommit() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        let commit = try #require(workflow.firstMatch(of: /VCPKG_COMMIT: ([0-9a-f]{40})/)?.1)
        let manifest = try Self.text("packaging/windows/vcpkg.json")
        #expect(manifest.contains("\"builtin-baseline\": \"\(commit)\""))
    }

    /// Package.swift links `debug/lib` for a debug build and `lib` for a release one (`ShimPortabilityTests` pins that), and the
    /// Windows job runs a debug suite and packages a release build: its vcpkg triplet must install both sets, which the
    /// release-only community triplet `x64-windows-release` does not (user decision 8).
    @Test func theWindowsJobInstallsBothTheDebugAndTheReleaseLibraries() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("--triplet x64-windows "))
        #expect(!workflow.contains("x64-windows-release"))
        #expect(workflow.contains(#"\debug\bin" >> $env:GITHUB_PATH"#), "the debug suite finds the debug DLLs")
    }

    /// Review focus: `actions/checkout` on windows-latest writes CRLF unless `.gitattributes` says otherwise, and the tests that
    /// read these files, and the scripts that run, need LF. The tests also read CRLF as LF, but a bash script cannot.
    @Test func gitattributesKeepsTheTextTheTestsReadAndTheScriptsRunAtLF() throws {
        let attributes = try Self.text(".gitattributes")
        for pattern in ["packaging/**", "scripts/**", ".github/**", "Sources/COCCT/**", "CLAUDE.md"] {
            #expect(attributes.contains("\n\(pattern) text eol=lf\n"), "\(pattern) must be checked out with LF")
        }
        #expect(attributes.contains("\npackaging/**/*.png binary\n"), "the icon is binary: an eol rule would rewrite its bytes")
    }

    /// Both Linux packages leave the Linux job as artifacts (user decision 2). The packer for the AppImage is fetched and pinned by
    /// `scripts/package-appimage.sh` (`AppImageRecipeTests`), so the workflow names no tool.
    @Test func theLinuxJobUploadsTheTarballAndTheAppImage() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("MetalCreator/dist/MetalCreator-*-linux-*.tar.gz\n"))
        #expect(workflow.contains("MetalCreator/dist/MetalCreator-*-linux-*.AppImage\n"))
        #expect(!workflow.contains("appimagetool"))
    }

    /// OpenCascade is built from a commit, not a tag (a tag can be moved).
    @Test func theLinuxImageBuildsOpenCascadeFromAFullCommit() throws {
        let dockerfile = try Self.text("scripts/linux/Dockerfile")
        #expect(dockerfile.firstMatch(of: /ARG OCCT_COMMIT=[0-9a-f]{40}\n/) != nil)
    }

    /// A file of the repository as text, "\r\n" read as "\n" (Swift counts "\r\n" as one Character, so a CRLF checkout would
    /// never match a pattern that ends in "\n").
    private static func text(_ path: String) throws -> String {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }
}
