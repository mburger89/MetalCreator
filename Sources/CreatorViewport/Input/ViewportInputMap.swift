/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits and middle-drag pans. The keys (F frames, + and − zoom) are
/// still window-wide stopgaps until MetalUI scopes keys to an element (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
    /// Orbit speed: radians of yaw or pitch per point dragged.
    public static let orbitRadiansPerPoint = 0.008
    /// ⌥-drag zoom: dragging up 100 points divides the camera distance by e.
    public static let zoomPerPoint = 0.01
    /// One + or − key press zooms by this factor.
    public static let keyZoomFactor = 1.25
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
