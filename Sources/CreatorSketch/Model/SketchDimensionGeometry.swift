import CreatorGeometry
import Foundation

/// Where a sketch's dimensions lie in world space (DIM-3): the same mapping the sketch editor draws (DIM-1), computed from
/// the solved points so a Sketch node can declare its dimensions to the viewport without the editor.
public enum SketchDimensionGeometry {
    /// World geometry of one dimension on `plane`, from the solved points: length and point–point distance linear between the
    /// points; point–line to the foot; radius/diameter radial toward the arc's middle (45° on a circle); angle angular at the
    /// corner. `nil` when its geometry is gone or degenerate.
    public static func geometry(of id: DimensionID, in sketch: Sketch, solution: SketchSolution, plane: Plane) -> DimensionGeometry? {
        guard let dimension = sketch.dimensions[id] else { return nil }
        let shape = { (entity: SketchEntityID) in self.shape(of: entity, sketch: sketch, solution: solution) }
        switch dimension.kind {
        case .length(let line):
            guard case .line(let a, let b)? = shape(line) else { return nil }
            return linear(a, b, on: plane)
        case .distance(let first, let second):
            switch (shape(first), shape(second)) {
            case (.point(let a)?, .point(let b)?):
                return linear(a, b, on: plane)
            case (.point(let p)?, .line(let a, let b)?), (.line(let a, let b)?, .point(let p)?):
                return linear(p, nearest(to: p, onLine: a, b), on: plane)
            default:
                return nil
            }
        case .radius(let curve), .diameter(let curve):
            return radial(shape(curve), on: plane)
        case .angle(let first, let second):
            guard case .line(let a, let b)? = shape(first), case .line(let c, let d)? = shape(second) else { return nil }
            let corner = intersection(a, b, c, d) ?? ((a + b + c + d) * 0.25)
            return .angular(vertex: plane.point(corner), first: plane.point((a + b) * 0.5), second: plane.point((c + d) * 0.5),
                            normal: plane.normal, placement: .standoff)
        }
    }

    /// A dimensioned entity's shape at its solved position.
    private enum Shape {
        case point(Vector2)
        case line(Vector2, Vector2)
        case circle(center: Vector2, radius: Double)
        /// `middle` is the polar angle halfway along the arc.
        case arc(center: Vector2, radius: Double, middle: Double)
    }

    private static func shape(of id: SketchEntityID, sketch: Sketch, solution: SketchSolution) -> Shape? {
        let at = { (point: SketchEntityID) in solution.points[point] ?? sketch.position(of: point) }
        switch sketch.entities[id]?.kind {
        case .point?:
            return at(id).map(Shape.point)
        case .line(let start, let end)?:
            guard let a = at(start), let b = at(end) else { return nil }
            return .line(a, b)
        case .circle(let center, _)?:
            guard let c = at(center), let radius = solution.radii[id] ?? sketch.radius(of: id) else { return nil }
            return .circle(center: c, radius: radius)
        case .arc(let center, let start, let end)?:
            guard let c = at(center), let s = at(start), let e = at(end) else { return nil }
            let first = atan2(s.y - c.y, s.x - c.x)
            let raw = wrapped(atan2(e.y - c.y, e.x - c.x) - first)
            let sweep = raw > 1e-12 ? raw : 2 * .pi
            return .arc(center: c, radius: (s - c).length, middle: first + sweep / 2)
        case .projected(let source)?:
            return source.isSuspended ? nil : shape(of: source.curve)
        case nil:
            return nil
        }
    }

    private static func shape(of curve: ProjectedCurve) -> Shape {
        switch curve {
        case .line(let a, let b): .line(a, b)
        case .circle(let center, let radius): .circle(center: center, radius: radius)
        case .arc(let center, let radius, let start, let end):
            .arc(center: center, radius: radius, middle: (start.radians + end.radians) / 2)
        }
    }

    /// A plane direction as a world direction.
    private static func world(_ v: Vector2, on plane: Plane) -> Vector3 {
        plane.xAxis * v.x + plane.yAxis * v.y
    }

    /// The length from `from` to `to`, measured along it and drawn on its upward side; `nil` for no length.
    private static func linear(_ from: Vector2, _ to: Vector2, on plane: Plane) -> DimensionGeometry? {
        let length = (to - from).length
        guard length > 1e-9 else { return nil }
        let direction = (to - from) * (1 / length)
        let left = Vector2(-direction.y, direction.x)
        // Upward, or rightward for a horizontal line, so the label sits above the part whichever way the line was drawn.
        let flip = left.y < -1e-9 || (abs(left.y) <= 1e-9 && left.x < 0)
        let side = flip ? left * -1 : left
        return .linear(from: plane.point(from), to: plane.point(to), direction: world(direction, on: plane),
                       side: world(side, on: plane), placement: .standoff)
    }

    /// An arc's radius leads out at the arc's middle, a circle's at 45 degrees; `nil` for another shape or a radius of 0.
    private static func radial(_ shape: Shape?, on plane: Plane) -> DimensionGeometry? {
        let (center, radius, angle): (Vector2, Double, Double)
        switch shape {
        case .arc(let c, let r, let middle)?: (center, radius, angle) = (c, r, middle)
        case .circle(let c, let r)?: (center, radius, angle) = (c, r, .pi / 4)
        default: return nil
        }
        guard radius > 1e-9 else { return nil }
        return .radial(center: plane.point(center), radius: radius, normal: plane.normal,
                       toward: world(Vector2(cos(angle), sin(angle)), on: plane), placement: .standoff)
    }

    private static func wrapped(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: turn)
        return value < 0 ? value + turn : value
    }

    /// The point of the infinite line through `a` and `b` nearest `p` (`a` when they coincide).
    private static func nearest(to p: Vector2, onLine a: Vector2, _ b: Vector2) -> Vector2 {
        let d = b - a
        let squared = d.x * d.x + d.y * d.y
        guard squared > 0 else { return a }
        return a + d * (((p.x - a.x) * d.x + (p.y - a.y) * d.y) / squared)
    }

    /// Where the infinite lines `a`–`b` and `c`–`d` meet; `nil` when they are parallel.
    private static func intersection(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Vector2? {
        let (r, s) = (b - a, d - c)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        return a + r * t
    }
}
