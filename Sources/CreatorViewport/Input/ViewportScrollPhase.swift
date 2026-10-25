/// Where a scroll event sits in its gesture, as the viewport needs it (MetalUI's `ScrollEvent` phases). A wheel zooms
/// toward the cursor; a trackpad's two-finger scroll pans.
public enum ViewportScrollPhase: Hashable, Sendable {
    /// A wheel mouse's step: no gesture around it. It zooms; the camera settles once the wheel has been still for
    /// `ViewportInputMap.wheelSettleDelay`.
    case step
    /// A precise device's scroll with no gesture phase around it (it is not a wheel: its delta is in points). It pans;
    /// the camera settles once it has been still for `wheelSettleDelay`.
    case preciseStep
    /// A trackpad scroll begins or continues. It pans; the camera settles when the scroll and its momentum end.
    case moving
    /// The system cancelled the scroll (the window lost key): the camera settles at once.
    case cancelled
    /// The fingers lifted. Momentum may follow; if none does within
    /// `wheelSettleDelay`, the camera settles.
    case ended
    /// The glide after the fingers lift. It keeps panning.
    case momentum
    /// The glide's last event (or its cancellation): the camera settles.
    case momentumEnded
}
