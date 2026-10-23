import CreatorKernel
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Foundation
import Testing
@testable import CreatorApp

/// `MetalCreator --self-test` (packaging): every check runs and is reported, a failure is worded, and the exports'
/// scratch folder is removed. The packaged run, with Homebrew unreadable, is `scripts/verify-app.sh`.
@MainActor
struct SelfTestTests {
    #if canImport(CreatorOCCT)
    @Test func onOCCTEveryCheckPassesAndTheScratchFolderIsRemoved() async {
        let scratch = Self.scratch()
        let report = await SelfTest.run(kernel: OCCTKernel(), scratch: scratch)
        #expect(report.results.map(\.name) == ["kernel", "STEP export", "STL export", "shaders", "implicit engine"] + Self.compilerCheck)
        #expect(report.passed, "\(report.text)")
        #expect(report.results.first?.detail.hasPrefix("a 10 mm cube, 1000 mm³, meshed into ") == true)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }
    #endif

    @Test func aFailingCheckIsReportedInWordsFailsTheRunAndStillRemovesTheScratchFolder() async {
        struct NoBundle: Error, CustomStringConvertible {
            var description: String { "no shader bundle" }
        }
        let scratch = Self.scratch()
        let report = await SelfTest.run(kernel: FakeKernel(), scratch: scratch) { throw NoBundle() }
        #expect(!report.passed)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
        // The implicit engine's lines depend on the machine and the compiler's on the package; the others are pinned exactly.
        let machineDependent: Set = ["implicit engine", "implicit compiler"]
        #expect(report.results.filter { !machineDependent.contains($0.name) } == [
            SelfTestResult(name: "kernel", passed: true, detail: "a 10 mm cube, 1000 mm³, meshed into 12 triangles"),
            SelfTestResult(name: "STEP export", passed: false, detail: "Export isn't supported by this kernel yet."),
            SelfTestResult(name: "STL export", passed: false, detail: "Export isn't supported by this kernel yet."),
            SelfTestResult(name: "shaders", passed: false, detail: "no shader bundle"),
        ])
        let lines = report.text.split(whereSeparator: \.isNewline).filter { !$0.contains("implicit ") }
        #expect(lines.joined(separator: "\n") == """
            MetalCreator \(AppBundleInfo.version) (\(AppBundleInfo.build)) self-test
            ok   kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles
            FAIL STEP export: Export isn't supported by this kernel yet.
            FAIL STL export: Export isn't supported by this kernel yet.
            FAIL shaders: no shader bundle
            """)
        #expect(report.results.last?.name == (Self.compilerCheck.last ?? "implicit engine"))
        #expect(report.results.first { $0.name == "implicit engine" }?.passed == true)
    }

    /// The scratch folder can't be made when something that is not a folder is in the way: that is a failed check of its
    /// own, and the exports (which have nowhere to write) fail beside it instead of the run stopping.
    @Test func ifTheScratchFolderCantBeMadeThatIsReportedAndTheRestStillRuns() async throws {
        let blocker = Self.scratch()
        try Data("in the way".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let report = await SelfTest.run(kernel: FakeKernel(), scratch: blocker.appending(path: "inside")) { }
        let expected = ["kernel", "scratch folder", "STEP export", "STL export", "shaders", "implicit engine"] + Self.compilerCheck
        #expect(report.results.map(\.name) == expected)
        #expect(!report.passed)
        let scratch = try #require(report.results.first { $0.name == "scratch folder" })
        #expect(!scratch.passed && !scratch.detail.isEmpty)
        #expect(report.results.first?.passed == true && report.results.first { $0.name == "implicit engine" }?.passed == true)
    }

    @Test func aReportWithNoChecksHasNotPassed() {
        #expect(!SelfTestReport(results: []).passed)
    }

    /// Linux and Windows have no OpenCascade until xp-2: the geometry checks are left out, not failed, so the run still tells
    /// whether the rest ships.
    @Test func onAPlatformWithoutAKernelTheGeometryChecksAreSkippedAndTheRunPasses() async {
        let scratch = Self.scratch()
        let report = await SelfTest.run(kernel: KernelUnavailable(), scratch: scratch) { }
        #expect(report.passed, "\(report.text)")
        #expect(report.results.map(\.name) == ["kernel", "STEP export", "STL export", "shaders", "implicit engine"] + Self.compilerCheck)
        let skipped = "skipped: Geometry isn't available on this platform yet."
        #expect(report.results.prefix(3).map(\.detail) == [skipped, skipped, skipped])
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    #if !canImport(Metal)
    @Test func offMacOSTheShaderCheckFindsTheSDLBackendsCompiledShaders() throws {
        try SelfTest.compileShaders()
    }
    #endif

    /// The check `--self-test` adds after "implicit engine" where the engine compiles its HLSL at run time (Linux and Windows; plan xp-c task 12).
    private static var compilerCheck: [String] {
        #if canImport(Metal)
        []
        #else
        ["implicit compiler"]
        #endif
    }

    private static func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "SelfTestTests-\(UUID().uuidString)")
    }
}
