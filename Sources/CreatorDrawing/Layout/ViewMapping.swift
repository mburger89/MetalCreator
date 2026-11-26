import CreatorGeometry

/// How a view maps a model-plane point to the sheet: `m x scale + offset` (plan Global Constraints). Views never rotate.
public struct ViewMapping: Hashable, Sendable {
    public var scale: Double
    public var offset: Vector2

    public init(scale: Double, offset: Vector2) {
        self.scale = scale
        self.offset = offset
    }

    public func sheet(_ model: Vector2) -> Vector2 { model * scale + offset }

    public func model(_ sheet: Vector2) -> Vector2 { (sheet - offset) * (1 / scale) }
}
