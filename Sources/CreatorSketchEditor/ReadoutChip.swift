import CreatorViewport

/// Where the pointer readout's chip sits, in viewport points (y down), inside the model area (the view less the
/// panels covering its edges, `ViewportProjector.modelArea`): centred on the pointer, `gap` above it; flipped `gap`
/// below it when it would rise within `margin` of the model area's top; kept `margin` inside the model area's sides.
/// A model area too small to hold the chip and its margins (narrower than the chip, or too short for it above or below
/// the pointer) shows none. Its width is the text's measured width (`TextMeasure`, MetalUI's text system through the view)
/// plus `padding` at each side, so drawing and placement agree for any string.
public struct ReadoutChip: Hashable, Sendable {
    /// Points between the pointer and the chip's nearer edge: clear of the crosshair.
    public static let gap = 14.0
    /// Points kept between the chip and the model area's edges.
    public static let margin = 4.0
    /// The chip's height and the padding at each side of its text.
    public static let height = 22.0
    public static let padding = 8.0

    public var text: String
    /// The chip's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    /// The chip that holds `text`: its measured width, rounded up to a whole point (a laid-out frame is rounded, so the
    /// text never wraps for want of a fraction), and `padding` at each side. The inference chip is sized the same way.
    @MainActor
    public static func size(of text: String, measuring measure: TextMeasure) -> ViewportSize {
        ViewportSize(width: measure(text).width.rounded(.up) + 2 * padding, height: height)
    }

    @MainActor
    public init?(text: String, pointer: ScreenPoint, in view: ViewportSize, modelArea: ViewportInsets = ViewportInsets(),
                 measuring measure: TextMeasure) {
        let width = Self.size(of: text, measuring: measure).width
        let left = modelArea.leading + Self.margin
        let right = view.width - modelArea.trailing - Self.margin
        let top = modelArea.top + Self.margin
        let bottom = view.height - modelArea.bottom - Self.margin
        guard right - left >= width else { return nil }
        let above = pointer.y - Self.gap - Self.height
        let below = pointer.y + Self.gap
        let y = above >= top ? above : below
        guard y >= top, y + Self.height <= bottom else { return nil }
        self.text = text
        size = ViewportSize(width: width, height: Self.height)
        origin = ScreenPoint(min(max(pointer.x - width / 2, left), right - width), y)
    }
}
