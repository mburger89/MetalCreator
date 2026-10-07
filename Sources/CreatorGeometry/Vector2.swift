/// A point or direction in a profile's 2D plane coordinates, in millimetres.
public struct Vector2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(0, 0)

    public static func + (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x - b.x, a.y - b.y) }
    public static func * (v: Vector2, s: Double) -> Vector2 { Vector2(v.x * s, v.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }
    public var isFinite: Bool { x.isFinite && y.isFinite }
}
