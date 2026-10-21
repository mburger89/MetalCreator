import CreatorGeometry

extension LatticeMapping {
    /// Points along the mapping's singular set that lie in `box`: where to look to see whether a region holds any of it (and the node
    /// should warn that cells there are left solid). Straight has none.
    public func singularSamples(in box: BoundingBox, count: Int = 64) -> [Vector3] {
        let line: (origin: Vector3, direction: Vector3)
        switch self {
        case .straight: return []
        case .cylindrical(let map): line = (map.origin, map.axis)
        case .spherical(let map): line = (map.centre, .unitZ)
        }
        let along = BoxProjection.corners(of: box).map { ($0 - line.origin).dot(line.direction) }
        guard let low = along.min(), let high = along.max() else { return [] }
        return (0..<count).map { line.origin + line.direction * (low + (high - low) * (Double($0) + 0.5) / Double(count)) }
            .filter { Self.contains(box, $0) }
    }

    /// Points on the half-plane where the mapping's angle is cut (and jumps by a turn) that lie in `box`, on a `steps` × `steps` grid.
    /// Straight has none.
    public func cutSamples(in box: BoundingBox, steps: Int = 16) -> [Vector3] {
        let frame: (origin: Vector3, away: Vector3, along: Vector3)
        switch self {
        case .straight: return []
        case .cylindrical(let map): frame = (map.origin, -map.reference, map.axis)
        case .spherical(let map): frame = (map.centre, -.unitX, .unitZ)
        }
        let corners = BoxProjection.corners(of: box)
        let heights = corners.map { ($0 - frame.origin).dot(frame.along) }
        let reaches = corners.map { ($0 - frame.origin).length }
        guard let low = heights.min(), let high = heights.max(), let far = reaches.max() else { return [] }
        var points: [Vector3] = []
        for i in 0..<steps {
            for j in 0..<steps {
                let reach = far * (Double(i) + 0.5) / Double(steps)
                let height = low + (high - low) * (Double(j) + 0.5) / Double(steps)
                let point = frame.origin + frame.away * reach + frame.along * height
                if Self.contains(box, point) { points.append(point) }
            }
        }
        return points
    }

    private static func contains(_ box: BoundingBox, _ p: Vector3) -> Bool {
        p.x >= box.min.x && p.x <= box.max.x && p.y >= box.min.y && p.y <= box.max.y && p.z >= box.min.z && p.z <= box.max.z
    }
}
