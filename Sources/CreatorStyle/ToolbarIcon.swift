import MetalUI

/// A toolbar icon (toolbar-icons): a bundled symbol in a fixed 24 x 24 box, so a borderless button or menu around it
/// has a hit box as large as the text buttons it replaced (24 tall) rather than the glyph's own few points. A press that
/// just misses the glyph then lands on the control, and not on the viewport (an orbit) or SDL's window drag handle.
///
/// Used as the `label` of a borderless `Button` or `Menu` in the top bar, the graph header and the view cube's controls,
/// and as a segment of the header's dock picker. A function, not a `Component`, so a caller can chain modifiers on it.
public enum ToolbarIcon {
    /// The side of the hit box, in points.
    public static let side: Float = 24

    @MainActor
    public static func image(_ name: String) -> some Element {
        Image(systemName: name)
            .frame(width: Pixels(side), height: Pixels(side))
            .contentShape(Rectangle())
    }

    /// The same, carrying its own accessibility label (`accessibilityLabel` is the glyph's, so it comes before the frame):
    /// and its tooltip, for a segment of a picker, which has no button around it to carry one.
    @MainActor
    public static func image(_ name: String, accessibilityLabel label: String, help: String) -> some Element {
        Image(systemName: name)
            .accessibilityLabel(label)
            .frame(width: Pixels(side), height: Pixels(side))
            .contentShape(Rectangle())
            .help(help)
    }
}
