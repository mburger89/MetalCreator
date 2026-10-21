import Testing
@testable import CreatorApp

/// The executable's command line (packaging): a file to open, or a headless flag the packaging script uses.
struct LaunchCommandTests {
    @Test func noArgumentsOpensAnEmptyWindowAndAPathOpensThatFile() {
        #expect(LaunchCommand(arguments: []) == .run(paths: []))
        #expect(LaunchCommand(arguments: ["bracket.mcgraph"]) == .run(paths: ["bracket.mcgraph"]))
    }

    @Test func theHeadlessFlags() {
        #expect(LaunchCommand(arguments: ["--version"]) == .version)
        #expect(LaunchCommand(arguments: ["--self-test"]) == .selfTest)
        #expect(LaunchCommand(arguments: ["--info-plist", "27.0"]) == .infoPlist(minimumSystemVersion: "27.0"))
    }

    @Test func theSmokeTestTakesAnOptionalNumberOfSeconds() {
        #expect(LaunchCommand(arguments: ["--smoke-test"]) == .smokeTest(seconds: 5))
        #expect(LaunchCommand(arguments: ["--smoke-test", "2.5"]) == .smokeTest(seconds: 2.5))
    }

    @Test(arguments: ["0", "-1", "soon", "601", "nan", "inf"])
    func aBadSmokeTestDurationIsAUsageError(_ seconds: String) {
        #expect(LaunchCommand(arguments: ["--smoke-test", seconds])
            == .usageError("--smoke-test takes a number of seconds between 0 and 600."))
    }

    @Test func aSecondValueAfterTheSmokeTestIsAUsageError() {
        #expect(LaunchCommand(arguments: ["--smoke-test", "5", "6"]) == .usageError("--smoke-test takes at most one number of seconds."))
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
        #expect(LaunchCommand(arguments: arguments) == .run(paths: []))
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

    /// A Linux file manager runs `MetalCreator %F` and Explorer `MetalCreator.exe "%1"`: every leading argument is a document
    /// (xp-2, gap XP-G5). The app opens each in turn and the last stays open. Arguments from the first flag on (Xcode appends
    /// its own after the file) are not files.
    @Test func everyLeadingArgumentIsADocumentAndTheFirstFlagEndsThem() {
        #expect(LaunchCommand(arguments: ["a.mcgraph", "b.mcgraph"]) == .run(paths: ["a.mcgraph", "b.mcgraph"]))
        #expect(LaunchCommand(arguments: ["a.mcgraph", "-NSDocumentRevisionsDebugMode", "YES"]) == .run(paths: ["a.mcgraph"]))
    }

    /// Review focus: a path with spaces or non-ASCII letters arrives as one argument and stays one document.
    @Test func aPathWithSpacesAndAccentsIsOneDocument() {
        let path = "/home/zoë/My Parts/Halterung Größe 2.mcgraph"
        #expect(LaunchCommand(arguments: [path]) == .run(paths: [path]))
    }

    @Test func onlyExistingDocumentsAreForwardedToTheRunningInstance() {
        let existing: Set<String> = ["a.mcgraph", "b.mcgraph"]
        #expect(LaunchCommand.forwardedDocuments(paths: ["a.mcgraph", "gone.mcgraph", "b.mcgraph"]) { existing.contains($0) }
            == ["a.mcgraph", "b.mcgraph"])
        #expect(LaunchCommand.forwardedDocuments(paths: []) { _ in true }.isEmpty)
    }
}
