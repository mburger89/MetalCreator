import CreatorGeometry

/// The shortest distance between two measured elements and the points that realise it.
public struct ShapeDistance: Sendable, Hashable {
    /// Millimetres.
    public var distance: Double
    /// The nearest point on the first element.
    public var from: Vector3
    /// The nearest point on the second element.
    public var to: Vector3

    public init(distance: Double, from: Vector3, to: Vector3) {
        self.distance = distance
        self.from = from
        self.to = to
    }
}
