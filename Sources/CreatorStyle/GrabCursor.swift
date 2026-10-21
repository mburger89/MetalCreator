import MetalUI

/// The closed hand shown while the canvas or the viewport is panned by a drag (`CanvasCursor.grabbing`,
/// `ViewportCursor.grabbing`).
///
/// On macOS it is the system's closed hand, `.grabActive`, unchanged. SDL has no hand: MetalUI draws `.grabActive` as its move
/// cursor and bundles no art (MetalUI S4, gap XP-G8; `docs/guides/input.md`, "How do I give a region my own cursor"), so on Linux
/// and Windows the app draws the hand itself, once, in code, and puts it on the region with `.image`.
public enum GrabCursor {
    /// Whether this platform has no closed hand of its own and so needs the drawn one: SDL's platforms, not macOS.
    public static let needsDrawnHand: Bool = {
        #if os(Linux) || os(Windows)
        true
        #else
        false
        #endif
    }()

    /// The pointer style: the drawn hand where `drawnHand` says so (a test passes it), the system's closed hand otherwise.
    @MainActor public static func pointerStyle(drawnHand: Bool = needsDrawnHand) -> PointerStyle {
        drawnHand ? .image(Image(decorative: bitmap, scale: 2), hotSpot: .center) : .grabActive
    }

    /// Pixels on a side of `bitmap`; at scale 2 the cursor is 24 points.
    static let side = 48

    /// The hand, built once so the pointer style's identity (the bitmap's) stays the same from frame to frame.
    static let bitmap = ImageBitmap(width: side, height: side, rgba: HandArt.rgba(side: side))
}
