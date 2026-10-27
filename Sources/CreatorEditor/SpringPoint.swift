import CreatorGeometry

/// How far one control point of a slack piece is from its taut place, and how fast it moves (cable ties spec §5.2), in
/// display canvas points and points a second.
public struct SpringPoint: Equatable, Sendable {
    public var offset: Vector2
    public var velocity: Vector2

    public init(offset: Vector2 = .zero, velocity: Vector2 = .zero) {
        self.offset = offset
        self.velocity = velocity
    }
}
