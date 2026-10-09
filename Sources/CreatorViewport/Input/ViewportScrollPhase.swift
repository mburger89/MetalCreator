/// Where a scroll event sits in its gesture, as the viewport's zoom needs it (MetalUI's `ScrollEvent` phases).
public enum ViewportScrollPhase: Hashable, Sendable {
    /// A wheel mouse's step: no gesture around it. It zooms; the camera settles once the wheel has been still for
    /// `ViewportInputMap.wheelSettleDelay`.
    case step
    /// A trackpad scroll begins or continues. It zooms; the camera settles when the scroll ends.
    case moving
    /// The fingers lifted (or the system cancelled the scroll): the camera settles.
    case ended
    /// The glide after the fingers lift. Zoom ignores it (docs/metalui-gaps.md C7 item 1).
    case momentum
}
