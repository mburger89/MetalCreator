/// What `MetalCreator --self-test` found: one ``SelfTestResult`` per check, in the order they ran.
public struct SelfTestReport: Equatable, Sendable {
    public var results: [SelfTestResult]

    public init(results: [SelfTestResult]) {
        self.results = results
    }

    /// Whether every check passed; the process exits 0 when it did and 1 otherwise.
    public var passed: Bool { !results.isEmpty && results.allSatisfy(\.passed) }

    /// The report as printed: a heading naming the version, then a line per check.
    public var text: String {
        (["\(AppBundleInfo.versionLine) self-test"] + results.map(\.line)).joined(separator: "\n")
    }
}
