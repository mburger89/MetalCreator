// Test fixture file: a clock the double-click tests move by hand.

/// A settable time for `EditorModel.now`.
@MainActor
final class TestClock {
    var now = ContinuousClock.now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}
