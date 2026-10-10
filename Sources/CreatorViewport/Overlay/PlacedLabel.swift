/// An overlay label on screen: the box the view draws it in, in viewport points (y down). The box is computed from the
/// text, never measured, so drawing and placement agree (as the sketch editor's readout chip is): `.caption` is 10 pt and
/// its widest characters (digits, "⌀", "°", "-") advance under 7 pt.
public struct PlacedLabel: Hashable, Sendable {
    public static let height = 20.0
    public static let characterWidth = 7.0
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

    /// The box that holds `text`.
    public static func size(of text: String) -> ViewportSize {
        ViewportSize(width: Double(text.count) * characterWidth + 2 * padding, height: height)
    }
}
