/// A handle's value beside its knob (spec §6.5), in viewport points (y down): `position` is the left end of the text's
/// vertical centre line, and `size` the box the text is measured to (`TextMeasure`), so a long value is never clipped.
public struct HandleLabel: Hashable, Sendable {
    /// The box's height: one line of `.caption`.
    public static let height = 18.0

    public var text: String
    public var position: ScreenPoint
    public var size: ViewportSize

    public init(text: String, position: ScreenPoint, size: ViewportSize) {
        self.text = text
        self.position = position
        self.size = size
    }

    /// The box's top-left corner: `position` is the middle of its left edge.
    public var origin: ScreenPoint {
        ScreenPoint(position.x, position.y - size.height / 2)
    }
}
