/// The time source for camera animations. The viewport reads it both when an animation starts and when it draws,
/// so it never needs to agree with MetalUI's display-link clock. Tests drive it by hand.
@MainActor
public protocol ViewportClock: AnyObject {
    /// Seconds on a monotonic clock.
    func now() -> Double
    /// The moment `seconds` from now. A caller reads it synchronously, before it starts the `Task` that sleeps, so the
    /// wait is measured from when it was asked for and not from when the task happens to get to run.
    func deadline(after seconds: Double) -> Double
    /// Suspends until `now()` reaches `deadline`, or the task is cancelled. Returns at once when it already has.
    func sleep(until deadline: Double) async
}

public extension ViewportClock {
    func deadline(after seconds: Double) -> Double { now() + seconds }
}
