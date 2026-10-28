import CreatorGeometry
import CreatorGraph

/// Helpers the nodes use to declare their dimensions (spec §3.1) while they evaluate.
enum DimensionSpecs {
    /// The most instances of one input a node dimensions individually.
    static let instanceLimit = 24

    /// The bounds of the profile's outer loop in plane coordinates, or `nil` for an empty one.
    static func planeBounds(of profile: Profile2D) -> (min: Vector2, max: Vector2)? {
        let points = profile.outer.flatMap(\.boundingPoints)
        guard let first = points.first else { return nil }
        var (low, high) = (first, first)
        for point in points {
            low = Vector2(min(low.x, point.x), min(low.y, point.y))
            high = Vector2(max(high.x, point.x), max(high.y, point.y))
        }
        return (low, high)
    }

    /// A unit vector at right angles to `direction`: `direction × z`, or `direction × x` when that is (nearly) zero.
    static func perpendicular(to direction: Vector3) -> Vector3 {
        if let result = direction.cross(.unitZ).normalized { return result }
        return direction.cross(.unitX).normalized ?? .unitX
    }

    /// One spec per instance (at most `instanceLimit`), or a single one carrying `count` when there are several
    /// and every value is equal (spec §3.1 "NX"). Empty for no instances; instances whose geometry is `nil` are left out.
    static func repeated(_ target: DimensionTarget, _ quantity: DimensionQuantity, values: [Double],
                         geometry: (Int) -> DimensionGeometry?) -> [DimensionSpec] {
        guard let first = values.first else { return [] }
        if values.count > 1, values.allSatisfy({ $0 == first }) {
            return geometry(0).map { [DimensionSpec(target, $0, quantity, value: first, count: values.count)] } ?? []
        }
        return values.prefix(instanceLimit).enumerated().compactMap { index, value in
            geometry(index).map { DimensionSpec(target, $0, quantity, value: value) }
        }
    }
}
