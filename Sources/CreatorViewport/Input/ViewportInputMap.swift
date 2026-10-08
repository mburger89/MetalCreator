/// The stopgap input bindings of spec §9, kept in one place so MetalUI's C7 input APIs can replace them
/// (docs/metalui-gaps.md): primary drag orbits, Shift-drag pans, ⌥-drag zooms, F frames, and + and − zoom.
public enum ViewportInputMap {
    /// Orbit speed: radians of yaw or pitch per point dragged.
    public static let orbitRadiansPerPoint = 0.008
    /// ⌥-drag zoom: dragging up 100 points divides the camera distance by e.
    public static let zoomPerPoint = 0.01
    /// One + or − key press zooms by this factor.
    public static let keyZoomFactor = 1.25
    /// A press that moves less than this many points before it is released is a click.
    public static let clickSlop = 3.0

    /// What a drag that begins with `modifiers` held does. Shift wins over ⌥.
    public static func dragMode(for modifiers: ViewportModifiers) -> ViewportDragMode {
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
