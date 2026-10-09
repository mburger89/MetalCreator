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

    @Test func aFailingCheckIsReportedInWordsAndFailsTheRun() async {
        struct NoBundle: Error, CustomStringConvertible {
            var description: String { "no shader bundle" }
        }
        let report = await SelfTest.run(kernel: FakeKernel(), scratch: Self.scratch()) { throw NoBundle() }
        #expect(!report.passed)
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

    @Test func aReportWithNoChecksHasNotPassed() {
        #expect(!SelfTestReport(results: []).passed)
    }

    private static func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "SelfTestTests-\(UUID().uuidString)")
    }
}
