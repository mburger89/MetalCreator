import CreatorKernel
import CreatorOCCT
import Foundation
import Testing
@testable import CreatorApp

/// `MetalCreator --self-test` (packaging): every check runs and is reported, a failure is worded, and the exports'
/// scratch folder is removed. The packaged run, with Homebrew unreadable, is `scripts/verify-app.sh`.
@MainActor
struct SelfTestTests {
    @Test func onOCCTEveryCheckPassesAndTheScratchFolderIsRemoved() async {
        let scratch = Self.scratch()
        let report = await SelfTest.run(kernel: OCCTKernel(), scratch: scratch)
        #expect(report.results.map(\.name) == ["kernel", "STEP export", "STL export", "shaders"])
        #expect(report.passed, "\(report.text)")
        #expect(report.results.first?.detail.hasPrefix("a 10 mm cube, 1000 mm³, meshed into ") == true)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test func aFailingCheckIsReportedInWordsFailsTheRunAndStillRemovesTheScratchFolder() async {
        struct NoBundle: Error, CustomStringConvertible {
            var description: String { "no shader bundle" }
        }
        let scratch = Self.scratch()
        let report = await SelfTest.run(kernel: FakeKernel(), scratch: scratch) { throw NoBundle() }
        #expect(!report.passed)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
        #expect(report.results == [
            SelfTestResult(name: "kernel", passed: true, detail: "a 10 mm cube, 1000 mm³, meshed into 12 triangles"),
            SelfTestResult(name: "STEP export", passed: false, detail: "Export isn't supported by this kernel yet."),
            SelfTestResult(name: "STL export", passed: false, detail: "Export isn't supported by this kernel yet."),
            SelfTestResult(name: "shaders", passed: false, detail: "no shader bundle"),
        ])
        #expect(report.text == """
            MetalCreator \(AppBundleInfo.version) (\(AppBundleInfo.build)) self-test
            ok   kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles
            FAIL STEP export: Export isn't supported by this kernel yet.
            FAIL STL export: Export isn't supported by this kernel yet.
            FAIL shaders: no shader bundle
            """)
    }

    /// The scratch folder can't be made when something that is not a folder is in the way: that is a failed check of its
    /// own, and the exports (which have nowhere to write) fail beside it instead of the run stopping.
    @Test func ifTheScratchFolderCantBeMadeThatIsReportedAndTheRestStillRuns() async throws {
        let blocker = Self.scratch()
        try Data("in the way".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let report = await SelfTest.run(kernel: FakeKernel(), scratch: blocker.appending(path: "inside")) { }
        #expect(report.results.map(\.name) == ["kernel", "scratch folder", "STEP export", "STL export", "shaders"])
        #expect(!report.passed)
        let scratch = try #require(report.results.first { $0.name == "scratch folder" })
        #expect(!scratch.passed && !scratch.detail.isEmpty)
        #expect(report.results.first?.passed == true && report.results.last?.passed == true)
    }

    @Test func aReportWithNoChecksHasNotPassed() {
        #expect(!SelfTestReport(results: []).passed)
    }

    private static func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "SelfTestTests-\(UUID().uuidString)")
    }
}
