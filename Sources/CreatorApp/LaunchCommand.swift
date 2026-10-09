/// What the `MetalCreator` executable was asked to do by its command line (arguments after the program's name).
/// Everything but ``run(path:)`` prints and exits without opening a window, so the packaging script and a terminal
/// can use the packaged binary headlessly.
public enum LaunchCommand: Equatable, Sendable {
    /// Open the window, and the `.mcgraph` file at `path` if one is named.
    case run(path: String?)
    /// `--version`: print ``AppBundleInfo/versionLine``.
    case version
    /// `--self-test`: run ``SelfTest`` and exit 0 when every check passes, 1 otherwise.
    case selfTest
    /// `--info-plist <minimum macOS>`: print the bundle's `Info.plist` (``AppBundleInfo``).
    case infoPlist(minimumSystemVersion: String)
    /// A flag this program doesn't take, or one missing its value: print the message and ``usage``, exit 64.
    case usageError(String)

    /// The flags, as `--help` would list them.
    public static let usage = """
        usage: MetalCreator [file.mcgraph]
               MetalCreator --version
               MetalCreator --self-test
               MetalCreator --info-plist <minimum macOS, e.g. 26.0>
        """

    public init(arguments: [String]) {
        guard let first = arguments.first else {
            self = .run(path: nil)
            return
        }
        switch first {
        case "--version":
            self = arguments.count == 1 ? .version : .usageError("--version takes no value.")
        case "--self-test":
            self = arguments.count == 1 ? .selfTest : .usageError("--self-test takes no value.")
        case "--info-plist":
            guard arguments.count == 2, let minimum = arguments.last, minimum.wholeMatch(of: /\d+(\.\d+){0,2}/) != nil else {
                self = .usageError("--info-plist takes one macOS version, like 26.0.")
                return
            }
            self = .infoPlist(minimumSystemVersion: minimum)
        default:
            if first.hasPrefix("--") {
                self = .usageError("Unknown option \(first).")
            } else {
                // Anything else starting with "-" is the system's (a `-psn_…` process serial number, or an
                // `-NSSomeDefault value` pair), not a file.
                self = .run(path: first.hasPrefix("-") ? nil : first)
            }
        }
    }
}
