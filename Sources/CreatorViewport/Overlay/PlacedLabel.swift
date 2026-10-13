/// An overlay label on screen: the box the view draws it in, in viewport points (y down). The box is the text's measured
/// width (`TextMeasure`, MetalUI's text system through the view) plus `padding` at each side, so drawing and placement
/// agree for any string, from "3" to a long value or a wide script, as the sketch editor's readout chip does.
public struct PlacedLabel: Hashable, Sendable {
    public static let height = 20.0
    public static let padding = 6.0

    public var text: String
    public var tint: OverlayTint
    /// The box's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init(text: String, tint: OverlayTint, origin: ScreenPoint, size: ViewportSize) {
        self.text = text
        self.tint = tint
        self.origin = origin
        self.size = size
    }

    /// The box that holds `text`: its measured width, rounded up to a whole point (a laid-out frame is rounded, so the text
    /// never wraps for want of a fraction), and `padding` at each side.
    @MainActor
    public static func box(of text: String, measuring measure: TextMeasure) -> ViewportSize {
        ViewportSize(width: measure(text).width.rounded(.up) + 2 * padding, height: height)
    }
}
