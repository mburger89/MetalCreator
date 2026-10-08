// Test fixture file: a clock the tests move by hand.
@testable import CreatorViewport

/// Starts at 100 s. `sleep` jumps time forward by the requested amount and returns at once, so an animation is
/// over as soon as its task runs.
@MainActor
final class ManualClock: ViewportClock {
    var time = 100.0

    func now() -> Double { time }

    func sleep(for seconds: Double) async {
        time += seconds
    }
}
