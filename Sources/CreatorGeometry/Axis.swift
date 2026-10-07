/// An infinite line used for revolves and rotations.
public struct Axis: Hashable, Sendable, Codable {
    public var origin: Vector3
    public var direction: Vector3

    public init(origin: Vector3, direction: Vector3) {
        self.origin = origin
        self.direction = direction
    }

    public static let z = Axis(origin: .zero, direction: .unitZ)
}
