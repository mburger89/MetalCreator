import Foundation

/// The real clock: system uptime, and `Task.sleep`.
@MainActor
public final class SystemViewportClock: ViewportClock {
    public init() {}

    public func now() -> Double { ProcessInfo.processInfo.systemUptime }

    public func sleep(for seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
