/// A straight piece of a dimension's drawing, in viewport points.
public struct ScreenSegment: Hashable, Sendable {
    public var a: ScreenPoint
    public var b: ScreenPoint

    public init(_ a: ScreenPoint, _ b: ScreenPoint) {
        self.a = a
        self.b = b
    }
}
