import CreatorGeometry
import Foundation

/// Where a footprint stands on the board, y up: scale, then turn counter-clockwise by `angle` degrees, then move.
public struct Placement2D: Sendable, Hashable {
    public var origin: Vector2
    public var angle: Double
    public var scale: Vector2

    public init(origin: Vector2 = .zero, angle: Double = 0, scale: Vector2 = Vector2(1, 1)) {
        self.origin = origin
        self.angle = angle
        self.scale = scale
    }

    public static let identity = Placement2D()

    public func apply(_ local: Vector2) -> Vector2 {
        let scaled = Vector2(local.x * scale.x, local.y * scale.y)
        return Placement2D.turn(scaled, byDegrees: angle) + origin
    }

    /// `point` turned counter-clockwise about the origin.
    static func turn(_ point: Vector2, byDegrees degrees: Double) -> Vector2 {
        guard degrees != 0 else { return point }
        let radians = degrees * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        return Vector2(point.x * cosine - point.y * sine, point.x * sine + point.y * cosine)
    }
}
