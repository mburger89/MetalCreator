/// The viewport's size in points.
public struct ViewportSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// True when either side is under one point or not finite: nothing can be drawn, navigated or picked.
    public var isEmpty: Bool {
        !(width.isFinite && height.isFinite && width >= 1 && height >= 1)
    }

    /// Width over height, or 1 for an empty size, so projections never divide by zero.
    public var aspect: Double { isEmpty ? 1 : width / height }

    public var center: ScreenPoint { ScreenPoint(width / 2, height / 2) }
}
