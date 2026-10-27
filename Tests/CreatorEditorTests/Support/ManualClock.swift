// Test fixture file: a clock the motion tests set by hand.
/// Seconds that move only when a test moves them; `EditorModel.motionClock` reads `now`.
@MainActor
final class ManualClock {
    var now = 1_000.0
}
