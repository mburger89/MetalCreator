import CreatorGeometry
import CreatorKernel

/// How far a through-all tool must run to leave the part (patterns spec §5): "reaches past the part's bounds". One
/// length serves every instance, so holes of one diameter share one tool whatever their placements.
enum ThroughReach {
    /// The diagonal of the box around the part and every placement's origin, and a millimetre more: from any origin
    /// in that box, in any direction, a tool this long has left the part.
    static func length(of part: Solid, placements: [Plane]) -> Double {
        let (low, high) = (part.bounds.min, part.bounds.max)
        let corners = (0..<8).map { corner in
            Vector3(corner & 1 == 0 ? low.x : high.x, corner & 2 == 0 ? low.y : high.y, corner & 4 == 0 ? low.z : high.z)
        }
        guard let box = BoundingBox(points: corners + placements.map(\.origin)) else { return 1 }
        return box.size.length + 1
    }
}
