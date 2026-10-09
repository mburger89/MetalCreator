/// The pointer's shape over the viewport (docs/metalui-gaps.md C7 item 5).
public enum ViewportCursor: Hashable, Sendable {
    /// Picking edges: a crosshair.
    case crosshair
    /// Orbiting or panning: a closed hand.
    case grabbing
}
