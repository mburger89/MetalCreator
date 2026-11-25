/// An axis-aligned rectangle in a plane, millimetres.
public struct Rect2D: Hashable, Sendable, Codable {
    public var min: Vector2
    public var max: Vector2

    public init(min: Vector2, max: Vector2) {
        self.min = min
        self.max = max
    }

    /// The smallest rectangle holding `points`, or `nil` for none.
    public init?(points: [Vector2]) {
        guard let first = points.first else { return nil }
        var low = first, high = first
        for point in points.dropFirst() {
            low = Vector2(Swift.min(low.x, point.x), Swift.min(low.y, point.y))
            high = Vector2(Swift.max(high.x, point.x), Swift.max(high.y, point.y))
        }
        self.init(min: low, max: high)
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
    public var center: Vector2 { Vector2((min.x + max.x) / 2, (min.y + max.y) / 2) }

    public func union(_ other: Rect2D) -> Rect2D {
        Rect2D(min: Vector2(Swift.min(min.x, other.min.x), Swift.min(min.y, other.min.y)),
               max: Vector2(Swift.max(max.x, other.max.x), Swift.max(max.y, other.max.y)))
    }

    public func contains(_ point: Vector2) -> Bool {
        point.x >= min.x && point.x <= max.x && point.y >= min.y && point.y <= max.y
    }

    public func intersects(_ other: Rect2D) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x && min.y <= other.max.y && max.y >= other.min.y
    }

    /// The rectangle shrunk by `amount` on every side; a negative amount grows it.
    public func insetBy(_ amount: Double) -> Rect2D {
        Rect2D(min: Vector2(min.x + amount, min.y + amount), max: Vector2(max.x - amount, max.y - amount))
    }
}
