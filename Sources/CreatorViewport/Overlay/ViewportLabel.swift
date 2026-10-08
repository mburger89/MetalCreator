/// A piece of text the viewport overlays at a point (triad axes, handle values).
public struct ViewportLabel: Hashable, Sendable {
    public var text: String
    public var position: ScreenPoint

    public init(text: String, position: ScreenPoint) {
        self.text = text
        self.position = position
    }
}
