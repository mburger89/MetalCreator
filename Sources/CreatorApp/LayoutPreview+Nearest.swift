import CreatorGeometry
import CreatorGraph

extension LayoutPreview {
    /// The distance between the two closest of `points` that are not in one place, or `nil` with fewer than two such points.
    /// Sorted along x and swept, so a few thousand scattered points cost a few thousand comparisons, not millions.
    static func nearestDistance(between points: [Vector3]) -> Double? {
        let sorted = points.sorted { $0.x < $1.x }
        var best = Double.infinity
        for (index, a) in sorted.enumerated() {
            for b in sorted[(index + 1)...] {
                if b.x - a.x >= best { break }
                let distance = (b - a).length
                if distance > 1e-9 { best = min(best, distance) }
            }
        }
        return best.isFinite ? best : nil
    }

    /// A scatter's triad length: `triadShare` of the distance between its two closest points (`singleTriad` for a lone point).
    /// A scatter's consecutive points are parent and child, so the step between them says nothing about its closest pair.
    static func scatterTriadLength(of planes: [Plane]) -> Double {
        guard let nearest = nearestDistance(between: planes.map(\.origin)) else { return singleTriad }
        return nearest * triadShare
    }
}
