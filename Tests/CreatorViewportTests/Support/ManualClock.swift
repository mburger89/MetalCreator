// Test fixture file: a clock the tests move by hand.
@testable import CreatorViewport

/// Starts at 100 s. `sleep` jumps time forward to the deadline and returns at once, so an animation is
/// over as soon as its task runs.
@MainActor
final class ManualClock: ViewportClock {
    var time = 100.0

    func now() -> Double { time }

    func sleep(until deadline: Double) async {
        time = max(time, deadline)
    }
}
