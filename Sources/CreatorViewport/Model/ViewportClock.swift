/// The time source for camera animations. The viewport reads it both when an animation starts and when it draws,
/// so it never needs to agree with MetalUI's display-link clock. Tests drive it by hand.
@MainActor
public protocol ViewportClock: AnyObject {
    /// Seconds on a monotonic clock.
    func now() -> Double
    func sleep(for seconds: Double) async
}
