/// An axis-aligned box in model space.
public struct BoundingBox: Hashable, Sendable, Codable {
    public var min: Vector3
    public var max: Vector3

    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }

    /// The smallest box containing `points`, or `nil` when there are none.
    public init?(points: [Vector3]) {
        guard let first = points.first else { return nil }
        var low = first
        var high = first
        for p in points.dropFirst() {
            low = Vector3(Swift.min(low.x, p.x), Swift.min(low.y, p.y), Swift.min(low.z, p.z))
            high = Vector3(Swift.max(high.x, p.x), Swift.max(high.y, p.y), Swift.max(high.z, p.z))
        }
        self.init(min: low, max: high)
    }

    public var size: Vector3 { max - min }
    public var center: Vector3 { (min + max) * 0.5 }

    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            min: Vector3(Swift.min(min.x, other.min.x), Swift.min(min.y, other.min.y), Swift.min(min.z, other.min.z)),
            max: Vector3(Swift.max(max.x, other.max.x), Swift.max(max.y, other.max.y), Swift.max(max.z, other.max.z))
        )
    }

    /// The overlap of two boxes, or `nil` if they don't overlap with positive volume.
    public func intersection(_ other: BoundingBox) -> BoundingBox? {
        let low = Vector3(Swift.max(min.x, other.min.x), Swift.max(min.y, other.min.y), Swift.max(min.z, other.min.z))
        let high = Vector3(Swift.min(max.x, other.max.x), Swift.min(max.y, other.max.y), Swift.min(max.z, other.max.z))
        guard low.x < high.x, low.y < high.y, low.z < high.z else { return nil }
        return BoundingBox(min: low, max: high)
    }

    public func translated(by offset: Vector3) -> BoundingBox {
        BoundingBox(min: min + offset, max: max + offset)
    }
}
