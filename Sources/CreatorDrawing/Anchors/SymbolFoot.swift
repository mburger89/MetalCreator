import CreatorGeometry
import CreatorKernel

/// Where a symbol stands on the geometry it holds (plan R2): computed from exact geometry, never a projected polyline.
public enum SymbolFoot {
    /// The foot in the view's model plane, the unit tangent there, and for a line its projected ends.
    public typealias Found = (foot: Vector2, along: Vector2, segment: (Vector2, Vector2)?)

    /// A segment's or an outline's infinite line nearest `hint` (so a hint beyond the edge's ends stands on its extension line),
    /// a face-on circle's nearest point; `.notLineOrCircle` for any other geometry.
    public static func of(_ geometry: AnchorGeometry, hint: Vector2, frame: ProjectionFrame) -> Result<Found, LostReason> {
        switch geometry {
        case .segment(let a, let b):
            let p = frame.place(a), q = frame.place(b)
            return onLine(through: p, toward: q - p, hint: hint, segment: (p, q))
        case .cylinder(let axisPoint, let axis, let radius, let side):
            guard let unit = axis.normalized else { return .failure(.notLineOrCircle) }
            var origin = frame.place(axisPoint)
            if side != 0, let across = unit.cross(frame.direction).normalized {
                origin += frame.place(across) * (side * radius)
            }
            return onLine(through: origin, toward: frame.place(unit), hint: hint, segment: nil)
        case .circle(let center, _, let radius, _):
            let c = frame.place(center)
            let toward = hint - c
            let length = toward.length
            let unit = length > 1e-12 ? toward * (1 / length) : Vector2(1, 0)
            return .success((c + unit * radius, Vector2(-unit.y, unit.x), nil))
        case .point, .other:
            return .failure(.notLineOrCircle)
        }
    }

    private static func onLine(
        through origin: Vector2, toward direction: Vector2, hint: Vector2, segment: (Vector2, Vector2)?
    ) -> Result<Found, LostReason> {
        let length = direction.length
        guard length > 1e-12 else { return .failure(.turnedAway) }
        let along = direction * (1 / length)
        let t = (hint - origin).x * along.x + (hint - origin).y * along.y
        return .success((origin + along * t, along, segment))
    }
}
