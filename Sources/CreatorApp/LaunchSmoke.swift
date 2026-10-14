import Foundation

/// `MetalCreator --smoke-test [seconds]` (CI, cross-platform spec §2.6): opens the real window over SDL's offscreen
/// renderers, lets it run, and reports whether it reached its first frame. The window's root calls ``frameReached()`` from
/// a `.task`, which MetalUI starts inside the first frame, so a run that never draws never sets it.
@MainActor
public final class LaunchSmoke {
    /// How long a smoke test runs when no number of seconds is given.
    public nonisolated static let defaultSeconds = 5.0

    public let seconds: Double
    public private(set) var reachedFirstFrame = false

    public init(seconds: Double = LaunchSmoke.defaultSeconds) {
        self.seconds = seconds
    }

    /// Called by the window's root once its first frame has been built.
    public func frameReached() {
        reachedFirstFrame = true
    }

    /// Whether the run passed: it reached its first frame.
    public var passed: Bool { reachedFirstFrame }

    /// The line printed when the time is up.
    public var report: String {
        if reachedFirstFrame {
            "MetalCreator smoke test: reached the first frame, ran \(seconds.formatted(.number)) s."
        } else {
            "MetalCreator smoke test: no frame was drawn in \(seconds.formatted(.number)) s."
        }
    }
}
