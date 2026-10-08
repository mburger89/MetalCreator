/// A point in the viewport, in points, measured from its top-left corner with y pointing down
/// (MetalUI's local gesture space).
public struct ScreenPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = ScreenPoint(0, 0)

    public static func + (a: ScreenPoint, b: ScreenPoint) -> ScreenPoint { ScreenPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: ScreenPoint, b: ScreenPoint) -> ScreenPoint { ScreenPoint(a.x - b.x, a.y - b.y) }

    public var length: Double { (x * x + y * y).squareRoot() }
}
