import CreatorGeometry
import Foundation

/// Where a sketch's dimensions lie in world space (DIM-3): the same mapping the sketch editor draws (DIM-1), computed from
/// the solved points so a Sketch node can declare its dimensions to the viewport without the editor.
public enum SketchDimensionGeometry {
    /// World geometry of one dimension on `plane`, from the solved points: length and point–point distance linear between the
    /// points; point–line to the foot; centre distance linear between the centres; line distance from the foot on the first line
    /// of the second's midpoint to that midpoint; horizontal and vertical distances linear along `plane.xAxis` / `plane.yAxis`;
    /// radius/diameter radial toward the arc's middle (45° on a circle); angle angular at the corner. A saved `labelPoint`
    /// places the text `.through` it (a radial one also aims `toward` it). `nil` when its geometry is gone or degenerate.
    public static func geometry(of id: DimensionID, in sketch: Sketch, solution: SketchSolution, plane: Plane) -> DimensionGeometry? {
        guard let dimension = sketch.dimensions[id] else { return nil }
        let label = dimension.labelPoint
        let shape = { (entity: SketchEntityID) in self.shape(of: entity, sketch: sketch, solution: solution) }
        switch dimension.kind {
        case .length(let line):
            guard case .line(let a, let b)? = shape(line) else { return nil }
            return linear(a, b, label: label, on: plane)
        case .distance(let first, let second):
            return distance(shape(first), shape(second), label: label, on: plane)
        case .centreDistance(let first, let second):
            guard let a = centre(shape(first)), let b = centre(shape(second)) else { return nil }
            return linear(a, b, label: label, on: plane)
        case .horizontalDistance(let first, let second), .verticalDistance(let first, let second):
            return axis(shape(first), shape(second), kind: dimension.kind, label: label, on: plane)
        case .lineDistance(let first, let second):
            return lineDistance(shape(first), shape(second), label: label, on: plane)
        case .radius(let curve), .diameter(let curve):
            return radial(shape(curve), label: label, on: plane)
        case .angle(let first, let second):
            return angular(shape(first), shape(second), label: label, on: plane)
        }
    }

    /// Between two points, or from a point to its foot on a line.
    private static func distance(_ first: Shape?, _ second: Shape?, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        switch (first, second) {
        case (.point(let a)?, .point(let b)?):
            return linear(a, b, label: label, on: plane)
        case (.point(let p)?, .line(let a, let b)?), (.line(let a, let b)?, .point(let p)?):
            return linear(p, nearest(to: p, onLine: a, b), label: label, on: plane)
        default:
            return nil
        }
    }

    /// At the lines' corner (their centroid when parallel), between their midpoints.
    private static func angular(_ first: Shape?, _ second: Shape?, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        guard case .line(let a, let b)? = first, case .line(let c, let d)? = second else { return nil }
        let corner = intersection(a, b, c, d) ?? ((a + b + c + d) * 0.25)
        return .angular(vertex: plane.point(corner), first: plane.point((a + b) * 0.5), second: plane.point((c + d) * 0.5),
                        normal: plane.normal, placement: placement(label, on: plane))
    }

    /// The distance between two centres along `plane.xAxis` (a horizontal distance) or `plane.yAxis`, its text on the side the label is on.
    private static func axis(_ first: Shape?, _ second: Shape?, kind: DimensionKind, label: Vector2?,
                             on plane: Plane) -> DimensionGeometry? {
        guard let a = centre(first), let b = centre(second) else { return nil }
        var horizontal = false
        if case .horizontalDistance = kind { horizontal = true }
        let middle = (a + b) * 0.5
        var sign = 1.0
        if let label, (horizontal ? label.y - middle.y : label.x - middle.x) < 0 { sign = -1 }
        let direction = horizontal ? Vector2(1, 0) : Vector2(0, 1)
        let side = horizontal ? Vector2(0, sign) : Vector2(sign, 0)
        return .linear(from: plane.point(a), to: plane.point(b), direction: world(direction, on: plane),
                       side: world(side, on: plane), placement: placement(label, on: plane))
    }

    /// From the foot on the first line of the second line's midpoint to that midpoint; `nil` when they coincide.
    private static func lineDistance(_ first: Shape?, _ second: Shape?, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        guard case .line(let a, let b)? = first, case .line(let c, let d)? = second else { return nil }
        let middle = (c + d) * 0.5
        let foot = nearest(to: middle, onLine: a, b)
        guard (middle - foot).length >= 1e-9 else { return nil }
        let along = unit(b - a)
        var sign = 1.0
        if let label {
            let halfway: Vector2 = (foot + middle) * 0.5
            let offset: Vector2 = label - halfway
            if offset.x * along.x + offset.y * along.y < 0 { sign = -1 }
        }
        return .linear(from: plane.point(foot), to: plane.point(middle), direction: world(unit(middle - foot), on: plane),
                       side: world(along * sign, on: plane), placement: placement(label, on: plane))
    }

    /// Where a point, or a circle's or arc's centre, lies; `nil` for a line.
    private static func centre(_ shape: Shape?) -> Vector2? {
        switch shape {
        case .point(let p)?: p
        case .circle(let c, _)?, .arc(let c, _, _)?: c
        default: nil
        }
    }

    /// `.through` the saved label point, else the style's standoff.
    private static func placement(_ label: Vector2?, on plane: Plane) -> DimensionPlacement {
        label.map { .through(plane.point($0)) } ?? .standoff
    }

    private static func unit(_ v: Vector2) -> Vector2 {
        let length = v.length
        return length > 1e-9 ? v * (1 / length) : .zero
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
    private static func linear(_ from: Vector2, _ to: Vector2, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        let length = (to - from).length
        guard length > 1e-9 else { return nil }
        let direction = unit(to - from)
        let left = Vector2(-(to - from).y / length, (to - from).x / length)
        // Upward, or rightward for a horizontal line, so the label sits above the part whichever way the line was drawn.
        let flip = left.y < -1e-9 || (abs(left.y) <= 1e-9 && left.x < 0)
        let side = flip ? left * -1 : left
        return .linear(from: plane.point(from), to: plane.point(to), direction: world(direction, on: plane),
                       side: world(side, on: plane), placement: placement(label, on: plane))
    }

    /// An arc's radius leads out at the arc's middle, a circle's at 45 degrees; `nil` for another shape or a radius of 0.
    private static func radial(_ shape: Shape?, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        let (center, radius, angle): (Vector2, Double, Double)
        switch shape {
        case .arc(let c, let r, let middle)?: (center, radius, angle) = (c, r, middle)
        case .circle(let c, let r)?: (center, radius, angle) = (c, r, .pi / 4)
        default: return nil
        }
        guard radius > 1e-9 else { return nil }
        var toward = Vector2(cos(angle), sin(angle))
        if let label, (label - center).length > 1e-9 { toward = unit(label - center) }
        return .radial(center: plane.point(center), radius: radius, normal: plane.normal,
                       toward: world(toward, on: plane), placement: placement(label, on: plane))
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
