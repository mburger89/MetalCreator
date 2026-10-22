import Foundation

/// `MetalCreator --smoke-test [seconds]` (CI, cross-platform spec §2.6): opens the real window over SDL's offscreen
/// renderers, lets it run, and reports whether it reached its first frame and whether the 3D viewport drew in it. The window's root
/// calls ``frameReached()`` from a `.task`, which MetalUI starts inside the first frame, so a run that never draws never sets it; the
/// viewport's count comes from ``viewport``, so a viewport whose GPU objects could not be made fails the run with the reason.
@MainActor
public final class LaunchSmoke {
    /// How long a smoke test runs when no number of seconds is given.
    public nonisolated static let defaultSeconds = 5.0

    /// What the 3D viewport has done so far: the main passes it drew and, if its GPU objects could not be made, why not.
    public struct ViewportReport: Sendable, Equatable {
        public var frames: Int
        public var failure: String?

        public init(frames: Int, failure: String?) {
            self.frames = frames
            self.failure = failure
        }
    }

    public let seconds: Double
    public private(set) var reachedFirstFrame = false
    /// Asks the app's viewport what it drew; `nil` for a run that has no viewport to check.
    public var viewport: (@MainActor () -> ViewportReport)?

    public init(seconds: Double = LaunchSmoke.defaultSeconds) {
        self.seconds = seconds
    }

    /// Called by the window's root once its first frame has been built.
    public func frameReached() {
        reachedFirstFrame = true
    }

    /// Whether the run passed: it reached its first frame and, where the viewport is checked, the viewport drew at least one.
    public var passed: Bool {
        guard reachedFirstFrame else { return false }
        return viewport.map { $0().frames > 0 } ?? true
    }

    /// The line printed when the time is up.
    public var report: String {
        let duration = seconds.formatted(.number)
        guard reachedFirstFrame else { return "MetalCreator smoke test: no frame was drawn in \(duration) s." }
        guard let state = viewport?() else { return "MetalCreator smoke test: reached the first frame, ran \(duration) s." }
        if state.frames > 0 {
            return "MetalCreator smoke test: reached the first frame and the 3D viewport drew \(state.frames.formatted()) "
                + "frame\(state.frames == 1 ? "" : "s"), ran \(duration) s."
        }
        let why = state.failure.map { ": \($0)" + ($0.hasSuffix(".") ? "" : ".") } ?? " (it was never asked to draw)."
        return "MetalCreator smoke test: reached the first frame, but the 3D viewport drew nothing\(why)"
    }
}
