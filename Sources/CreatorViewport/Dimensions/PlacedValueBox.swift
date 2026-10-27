/// The value box on screen: its top-left corner and size, in viewport points (y down).
public struct PlacedValueBox: Hashable, Sendable {
    public var box: DimensionValueBox
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init(box: DimensionValueBox, origin: ScreenPoint, size: ViewportSize) {
        self.box = box
        self.origin = origin
        self.size = size
    }
}
