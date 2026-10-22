/// What the `MetalCreator` executable was asked to do by its command line (arguments after the program's name).
/// Everything but ``run(paths:)`` prints and exits without opening a window, so the packaging script and a terminal
/// can use the packaged binary headlessly.
public enum LaunchCommand: Equatable, Sendable {
    /// Open the window, and the `.mcgraph` files at `paths`: every argument up to the first one that starts with "-" (a Linux
    /// file manager runs `MetalCreator %F` with all the selected files, Explorer `MetalCreator.exe "%1"`; Xcode appends its own
    /// flags after the file). Each file is handed to the app as Finder would (`App.open`, then `AppModel.openRequested(_:)`), so
    /// it gets the same unsaved-changes check, and the last one stays open.
    case run(paths: [String])
    /// `--version`: print ``AppBundleInfo/versionLine``.
    case version
    /// `--help`: print ``usage`` and exit 0.
    case help
    /// `--self-test`: run ``SelfTest`` and exit 0 when every check passes, 1 otherwise.
    case selfTest
    /// `--info-plist <minimum macOS>`: print the bundle's `Info.plist` (``AppBundleInfo``).
    case infoPlist(minimumSystemVersion: String)
    /// The documents a second launch hands to the running instance (Linux and Windows): the paths `run(paths:)` names that
    /// `exists` says are files, in order.
    public static func forwardedDocuments(paths: [String], exists: (String) -> Bool) -> [String] {
        paths.filter(exists)
    }

    /// `--smoke-test [seconds]` (CI): open the window over SDL's offscreen renderers for `seconds`, print whether it reached
    /// its first frame, and exit 0 when it did and 1 when not (``LaunchSmoke``). Only a build with the SDL backend can.
    case smokeTest(seconds: Double)
    /// A flag this program doesn't take, or one missing its value: print the message and ``usage``, exit 64.
    case usageError(String)

    /// The flags, as `--help` lists them.
    public static let usage = """
        usage: MetalCreator [file.mcgraph]
               MetalCreator --help
               MetalCreator --version
               MetalCreator --self-test
               MetalCreator --info-plist <minimum macOS, e.g. 26.0>
               MetalCreator --smoke-test [seconds]   (Linux and Windows builds; default 5 seconds)
        """

    public init(arguments: [String]) {
        guard let first = arguments.first else {
            self = .run(paths: [])
            return
        }
        switch first {
        case "--version":
            self = arguments.count == 1 ? .version : .usageError("--version takes no value.")
        case "--help":
            self = arguments.count == 1 ? .help : .usageError("--help takes no value.")
        case "--self-test":
            self = arguments.count == 1 ? .selfTest : .usageError("--self-test takes no value.")
        case "--info-plist":
            guard arguments.count == 2, let minimum = arguments.last, minimum.wholeMatch(of: /[0-9]+(\.[0-9]+){0,2}/) != nil else {
                self = .usageError("--info-plist takes one macOS version, like 26.0.")
                return
            }
            self = .infoPlist(minimumSystemVersion: minimum)
        case "--smoke-test":
            self = Self.smokeTest(arguments: arguments)
        default:
            if first.hasPrefix("--") {
                self = .usageError("Unknown option \(first).")
            } else {
                // Anything else starting with "-" is the system's (a `-psn_…` process serial number, or an
                // `-NSSomeDefault value` pair), not a file; so is everything after it.
                self = .run(paths: Array(arguments.prefix { !$0.hasPrefix("-") }))
            }
        }
    }

    /// `--smoke-test` with its optional number of seconds (`arguments` starts with the flag).
    private static func smokeTest(arguments: [String]) -> LaunchCommand {
        switch arguments.count {
        case 1:
            return .smokeTest(seconds: LaunchSmoke.defaultSeconds)
        case 2:
            guard let seconds = Double(arguments[1]), seconds.isFinite, seconds > 0, seconds <= 600 else {
                return .usageError("--smoke-test takes a number of seconds between 0 and 600.")
            }
            return .smokeTest(seconds: seconds)
        default:
            return .usageError("--smoke-test takes at most one number of seconds.")
        }
    }
}
