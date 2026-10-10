import CreatorGeometry
import CreatorKernel
import CreatorSketch
import Foundation

/// Projects a model edge onto a sketch plane (sketcher spec §7, "Projection, v1"): a line becomes a
/// 2D line, and a circle or arc whose axis is parallel to the plane normal becomes a 2D circle or
/// arc. Anything else is refused, with the reason for the node's warning.
public enum EdgeProjection {
    public enum Outcome: Equatable {
        case curve(ProjectedCurve)
        case refused(String)
    }

    /// How far a circle's axis may be from parallel to the plane normal, as 1 − |cos|.
    static let axisTolerance = 1e-9
    /// A projected line shorter than this (mm) is a point.
    static let pointTolerance = 1e-9

    static let toPoint = "it is perpendicular to the sketch plane, so it projects to a point"
    static let oblique = "it is a circle or arc that doesn't face the sketch plane"
    static let unsupported = "only lines, circles and arcs can be projected"

    public static func project(_ edge: EdgeInfo, onto plane: Plane) -> Outcome {
        switch edge.curve {
        case .line(let start, let end)?:
            let (a, b) = (local(start, on: plane), local(end, on: plane))
            return (b - a).length > pointTolerance ? .curve(.line(a, b)) : .refused(toPoint)
        case .circle(let center, let axis, let radius, let start, let sweep)?:
            guard let unit = axis.normalized, let normal = plane.normal.normalized,
                  abs(abs(unit.dot(normal)) - 1) <= axisTolerance else { return .refused(oblique) }
            let c = local(center, on: plane)
            if sweep >= 2 * .pi - 1e-9 { return .curve(.circle(center: c, radius: radius)) }
            let offset = local(start, on: plane) - c
            let from = atan2(offset.y, offset.x)
            // Counter-clockwise about an axis along the normal is counter-clockwise in the plane; about
            // an axis against it, clockwise, so the counter-clockwise arc then starts at the far end.
            let first = unit.dot(normal) > 0 ? from : from - sweep
            return .curve(.arc(center: c, radius: radius, start: Angle(radians: first), end: Angle(radians: first + sweep)))
        case nil:
            return .refused(unsupported)
        }
    }

    /// `point` in the plane's coordinates, projected along the normal.
    static func local(_ point: Vector3, on plane: Plane) -> Vector2 {
        let offset = point - plane.origin
        return Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
    }
}
