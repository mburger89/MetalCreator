/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits, middle-drag pans and two-finger scroll zooms toward the
/// cursor. The keys (F frames, + and − zoom) are still window-wide stopgaps until MetalUI scopes keys to an element
/// (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
    /// Orbit speed: radians of yaw or pitch per point dragged.
    public static let orbitRadiansPerPoint = 0.008
    /// ⌥-drag zoom: dragging up 100 points divides the camera distance by e.
    public static let zoomPerPoint = 0.01
    /// One + or − key press zooms by this factor.
    public static let keyZoomFactor = 1.25
    /// Scroll zoom: 100 points of scroll multiply or divide the camera distance by e. A wheel mouse's step is
    /// 10 points (MetalUI reports its lines × 10), so about 10%.
    public static let scrollZoomPerPoint = 0.01
    /// Wheel steps closer together than this many seconds are one zoom: the camera settles once, after the last
    /// (a free-spinning wheel sends tens of steps a second, spec §7.3).
    public static let wheelSettleDelay = 0.15
    /// How far a press moves before it drags. A primary press that moves less is a click (MetalUI's tap slop is
    /// also 5 points), and a right press that moves less opens the face menu.
    public static let dragThreshold = 5.0

    /// What a drag that begins with `button` pressed and `modifiers` held does. The middle button pans and the
    /// right button orbits, whatever is held. With the primary button Shift pans and ⌥ zooms; Shift wins over ⌥.
    public static func dragMode(for modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) -> ViewportDragMode {
        switch button {
        case .middle: return .pan
        case .secondary: return .orbit
        case .primary: break
        }
        if modifiers.contains(.shift) { return .pan }
        if modifiers.contains(.option) { return .zoom }
        return .orbit
    }

    /// The viewport's keys, in MetalUI keystroke spelling. `shift-+` sits beside `=` because MetalUI folds
    /// Shift into `charactersIgnoringModifiers` on that key and matches modifier sets exactly. The plain `+` is
    /// the numeric keypad's, which reports "+" with no Shift.
    public static let keyBindings: [(spelling: String, command: ViewportKeyCommand)] = [
        ("f", .frame), ("=", .zoomIn), ("shift-+", .zoomIn), ("+", .zoomIn), ("-", .zoomOut),
    ]
}
