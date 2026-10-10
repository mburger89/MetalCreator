// Test fixture file: a clock whose sleeps last until the test moves time past their deadline.
@testable import CreatorViewport

/// Starts at 100 s. `sleep(for:)` suspends until `time` reaches the moment it was asked at plus the delay, or the
/// task is cancelled, so a test can pin a debounce: advance short of the delay and nothing fires; advance past it and
/// it does. (`ManualClock`'s sleeps return at once, so a debounce can't be told from none.)
@MainActor
final class GatedClock: ViewportClock {
    var time = 100.0

    func now() -> Double { time }

    func sleep(for seconds: Double) async {
        let deadline = time + seconds
        while time < deadline, !Task.isCancelled { await Task.yield() }
    }

    /// Lets the sleeps already asked for begin (they read the time when they start), moves time on, and lets the tasks
    /// it wakes run.
    func advance(by seconds: Double) async {
        await settle()
        time += seconds
        await settle()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
