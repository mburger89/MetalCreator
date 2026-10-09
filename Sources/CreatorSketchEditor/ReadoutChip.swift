import CreatorViewport

/// Where the pointer readout's chip sits over the viewport, in viewport points (y down): centred on the pointer, `gap`
/// above it; flipped `gap` below it when it would leave the top; kept `margin` inside the view's sides. Its size is
/// computed from the text, never measured (editor geometry is computed, so drawing and placement agree).
public struct ReadoutChip: Hashable, Sendable {
    /// Points between the pointer and the chip's nearer edge: clear of the crosshair.
    public static let gap = 14.0
    /// Points kept between the chip and the view's edges.
    public static let margin = 4.0
    /// The chip's height, and its width per character and padding at each side (caption text).
    public static let height = 22.0
    public static let characterWidth = 7.0
    public static let padding = 8.0

    public var text: String
    /// The chip's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init(text: String, pointer: ScreenPoint, in view: ViewportSize) {
        self.text = text
        let width = Double(text.count) * Self.characterWidth + 2 * Self.padding
        size = ViewportSize(width: width, height: Self.height)
        let x = min(pointer.x - width / 2, view.width - Self.margin - width)
        let above = pointer.y - Self.gap - Self.height
        origin = ScreenPoint(max(x, Self.margin), above < Self.margin ? pointer.y + Self.gap : above)
    }
}
