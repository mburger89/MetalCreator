import Foundation

/// The real clock: system uptime, and `Task.sleep`.
@MainActor
public final class SystemViewportClock: ViewportClock {
    public init() {}

    public func now() -> Double { ProcessInfo.processInfo.systemUptime }

    public func sleep(until deadline: Double) async {
        let remaining = deadline - now()
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }
}
