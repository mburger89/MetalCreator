/// One line of a ``SelfTestReport``: what was checked, and what it found or why it failed.
public struct SelfTestResult: Equatable, Sendable {
    public var name: String
    public var passed: Bool
    /// What a passed check found, or why a failed one failed.
    public var detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }

    /// `ok   kernel: …` or `FAIL STEP export: …`, as `--self-test` prints it.
    public var line: String { "\(passed ? "ok  " : "FAIL") \(name): \(detail)" }
}
