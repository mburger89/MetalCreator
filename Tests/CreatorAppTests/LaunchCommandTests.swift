import Testing
@testable import CreatorApp

/// The executable's command line (packaging): a file to open, or a headless flag the packaging script uses.
struct LaunchCommandTests {
    @Test func noArgumentsOpensAnEmptyWindowAndAPathOpensThatFile() {
        #expect(LaunchCommand(arguments: []) == .run(path: nil))
        #expect(LaunchCommand(arguments: ["bracket.mcgraph"]) == .run(path: "bracket.mcgraph"))
    }

    @Test func theHeadlessFlags() {
        #expect(LaunchCommand(arguments: ["--version"]) == .version)
        #expect(LaunchCommand(arguments: ["--self-test"]) == .selfTest)
        #expect(LaunchCommand(arguments: ["--info-plist", "27.0"]) == .infoPlist(minimumSystemVersion: "27.0"))
    }

    @Test(arguments: ["26", "26.0", "26.0.1"])
    func infoPlistTakesAMacOSVersion(_ version: String) {
        #expect(LaunchCommand(arguments: ["--info-plist", version]) == .infoPlist(minimumSystemVersion: version))
    }

    @Test(arguments: [["--info-plist"], ["--info-plist", "latest"], ["--info-plist", "26.0", "27.0"]])
    func infoPlistWithoutOneVersionIsAUsageError(_ arguments: [String]) {
        #expect(LaunchCommand(arguments: arguments) == .usageError("--info-plist takes one macOS version, like 26.0."))
    }

    @Test func anUnknownFlagOrAStrayValueIsAUsageError() {
        #expect(LaunchCommand(arguments: ["--open", "a.mcgraph"]) == .usageError("Unknown option --open."))
        #expect(LaunchCommand(arguments: ["--version", "2"]) == .usageError("--version takes no value."))
        #expect(LaunchCommand(arguments: ["--self-test", "now"]) == .usageError("--self-test takes no value."))
    }

    /// Review focus: LaunchServices and Xcode may pass their own arguments (`-psn_…`, `-NSSomeDefault value`); the
    /// app opens its window rather than refusing them or opening one as a file.
    @Test(arguments: [["-psn_0_1234567"], ["-NSDocumentRevisionsDebugMode", "YES"], ["-AppleLanguages", "(de)"]])
    func theSystemsOwnArgumentsOpenAnEmptyWindow(_ arguments: [String]) {
        #expect(LaunchCommand(arguments: arguments) == .run(path: nil))
    }

    /// `\d` matches any script's digits; a macOS version is ASCII ("٢٦" is Arabic-Indic 26, "２６" fullwidth).
    @Test(arguments: ["٢٦", "２６", "26.٠"])
    func infoPlistTakesOnlyASCIIDigits(_ version: String) {
        #expect(LaunchCommand(arguments: ["--info-plist", version]) == .usageError("--info-plist takes one macOS version, like 26.0."))
    }

    @Test func helpPrintsTheUsageInsteadOfBeingAnUnknownOption() {
        #expect(LaunchCommand(arguments: ["--help"]) == .help)
        #expect(LaunchCommand(arguments: ["--help", "x"]) == .usageError("--help takes no value."))
        #expect(LaunchCommand.usage.contains("--help") && LaunchCommand.usage.contains("--self-test"))
    }

    /// Only the first file is opened; later arguments (Xcode appends its own after the file) are not files.
    @Test func argumentsAfterTheFileAreIgnored() {
        #expect(LaunchCommand(arguments: ["a.mcgraph", "b.mcgraph"]) == .run(path: "a.mcgraph"))
        #expect(LaunchCommand(arguments: ["a.mcgraph", "-NSDocumentRevisionsDebugMode", "YES"]) == .run(path: "a.mcgraph"))
    }
}
