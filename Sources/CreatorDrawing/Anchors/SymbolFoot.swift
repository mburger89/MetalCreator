import CreatorGeometry
import CreatorKernel
import Foundation

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
        case .circle(let center, let axis, let radius, let start, let sweep):
            return onArc(Arc(center: center, axis: axis, radius: radius, start: start, sweep: sweep), hint: hint, frame: frame)
        case .point, .other:
            return .failure(.notLineOrCircle)
        }
    }

    /// A circle's arc as `AnchorGeometry.circle` holds it.
    private struct Arc {
        var center: Vector3
        var axis: Vector3
        var radius: Double
        var start: Vector3
        var sweep: Double
    }

    /// The point of a circle nearest `hint`; on a partial arc only the arc's own points count, so a hint off its sweep stands on the
    /// nearer end (the foot lies on the arc, never on the rest of the full circle).
    private static func onArc(_ arc: Arc, hint: Vector2, frame: ProjectionFrame) -> Result<Found, LostReason> {
        let (center, axis, radius, start, sweep) = (arc.center, arc.axis, arc.radius, arc.start, arc.sweep)
        let c = frame.place(center)
        let toward = hint - c
        let length = toward.length
        var unit = length > 1e-12 ? toward * (1 / length) : Vector2(1, 0)
        let fullTurn = 2 * Double.pi
        if sweep < fullTurn - 1e-9, let n = axis.normalized {
            let u = start - center
            let first = frame.place(u), second = frame.place(n.cross(u))
            let turns = first.x * second.y - first.y * second.x >= 0 ? 1.0 : -1.0
            let a0 = atan2(first.y, first.x)
            var t = turns * (atan2(unit.y, unit.x) - a0)
            t -= fullTurn * (t / fullTurn).rounded(.down)
            if t > sweep {
                if fullTurn - t <= t - sweep {
                    unit = Vector2(first.x, first.y) * (1 / Swift.max(first.length, 1e-12))
                } else {
                    let end = a0 + turns * sweep
                    unit = Vector2(cos(end), sin(end))
                }
            }
        }
        return .success((c + unit * radius, Vector2(-unit.y, unit.x), nil))
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
