import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation

/// The labels the overlay shows for a sketch's dimensions (sketcher spec §8): where each kind sits, what it reads and the
/// role it is coloured in. Pure. The viewport projects the anchors with the camera and stands each label off its anchor
/// along `nudge`, so the editor needs no camera.
enum SketchDimensionLabels {
    /// A dimensioned entity's shape at its solved position.
    enum Shape {
        case point(Vector2)
        case line(Vector2, Vector2)
        case circle(center: Vector2, radius: Double)
        /// `middle` is the polar angle halfway along the arc.
        case arc(center: Vector2, radius: Double, middle: Double)
    }

    static func labels(sketch: Sketch, solution: SketchSolution, plane: Plane, conflicting: Set<DimensionID>) -> [OverlayLabel] {
        sketch.dimensionIDs.compactMap { id in
            guard let dimension = sketch.dimensions[id],
                  let place = placement(of: dimension.kind, sketch: sketch, solution: solution) else { return nil }
            let value = dimension.isDriving ? dimension.value : solution.measurements[id] ?? dimension.value
            let text = DimensionText.format(value, kind: dimension.kind)
            let reads = dimension.isDriving ? (dimension.isExposed ? "\(dimension.name) = \(text)" : text) : "(\(text))"
            let tint: OverlayTint = conflicting.contains(id) ? .conflicting : dimension.isDriving ? .fullyConstrained : .construction
            let away = place.away
            return OverlayLabel(reads, at: plane.point(place.anchor), tint: tint,
                                nudge: plane.xAxis * away.x + plane.yAxis * away.y)
        }
    }

    /// Where a dimension's label is anchored and which way (a unit vector in the plane) it stands off; `nil` when its
    /// geometry is gone or doesn't fit its kind.
    static func placement(of kind: DimensionKind, sketch: Sketch, solution: SketchSolution) -> (anchor: Vector2, away: Vector2)? {
        let shape = { (id: SketchEntityID) in self.shape(of: id, sketch: sketch, solution: solution) }
        switch kind {
        case .length(let id):
            guard case .line(let a, let b)? = shape(id) else { return nil }
            return ((a + b) * 0.5, normal(of: b - a) ?? up)
        case .radius(let id), .diameter(let id):
            return circlePlacement(shape(id))
        case .distance(let first, let second):
            return distancePlacement(shape(first), shape(second))
        case .angle(let first, let second):
            return anglePlacement(shape(first), shape(second))
        }
    }

    static let up = Vector2(0, 1)

    /// A radius or diameter: on the arc's middle, or a circle's upper right, standing off outwards.
    static func circlePlacement(_ shape: Shape?) -> (anchor: Vector2, away: Vector2)? {
        switch shape {
        case .arc(let center, let radius, let middle)?: onCircle(center, radius, middle)
        case .circle(let center, let radius)?: onCircle(center, radius, .pi / 4)
        default: nil
        }
    }

    /// Between two points, or between a point and its foot on a line.
    static func distancePlacement(_ first: Shape?, _ second: Shape?) -> (anchor: Vector2, away: Vector2)? {
        switch (first, second) {
        case (.point(let a)?, .point(let b)?):
            return ((a + b) * 0.5, normal(of: b - a) ?? up)
        case (.point(let p)?, .line(let a, let b)?), (.line(let a, let b)?, .point(let p)?):
            let foot = EditorGeometry.nearest(to: p, onLine: a, b)
            return ((p + foot) * 0.5, normal(of: foot - p) ?? up)
        default:
            return nil
        }
    }

    /// At the corner where the lines meet, standing off along the bisector of the two lines' middles.
    static func anglePlacement(_ first: Shape?, _ second: Shape?) -> (anchor: Vector2, away: Vector2)? {
        guard case .line(let a, let b)? = first, case .line(let c, let d)? = second else { return nil }
        let corner = intersection(a, b, c, d) ?? ((a + b + c + d) * 0.25)
        let away = unit(unit((a + b) * 0.5 - corner) + unit((c + d) * 0.5 - corner))
        return (corner, away == .zero ? up : away)
    }

    static func shape(of id: SketchEntityID, sketch: Sketch, solution: SketchSolution) -> Shape? {
        let at = { (point: SketchEntityID) in SketchOverlayBuilder.position(point, sketch, solution) }
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
            let first = EditorGeometry.angle(s - c)
            return .arc(center: c, radius: (s - c).length, middle: first + EditorGeometry.sweep(center: c, start: s, end: e) / 2)
        case .projected(let source)?:
            return source.isSuspended ? nil : shape(of: source.curve)
        case nil:
            return nil
        }
    }

    static func shape(of curve: ProjectedCurve) -> Shape {
        switch curve {
        case .line(let a, let b): .line(a, b)
        case .circle(let center, let radius): .circle(center: center, radius: radius)
        case .arc(let center, let radius, let start, let end):
            .arc(center: center, radius: radius, middle: (start.radians + end.radians) / 2)
        }
    }

    static func onCircle(_ center: Vector2, _ radius: Double, _ angle: Double) -> (anchor: Vector2, away: Vector2) {
        let direction = Vector2(cos(angle), sin(angle))
        return (center + direction * radius, direction)
    }

    /// `v` turned a quarter, as a unit vector pointing up (or, for a horizontal `v`, right); `nil` for no length.
    static func normal(of v: Vector2) -> Vector2? {
        let length = v.length
        guard length > 1e-9 else { return nil }
        let left = Vector2(-v.y / length, v.x / length)
        let flip = left.y < -1e-9 || (abs(left.y) <= 1e-9 && left.x < 0)
        return flip ? left * -1 : left
    }

    static func unit(_ v: Vector2) -> Vector2 {
        let length = v.length
        return length > 1e-9 ? v * (1 / length) : .zero
    }

    /// Where the infinite lines `a`–`b` and `c`–`d` meet; `nil` when they are parallel.
    static func intersection(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Vector2? {
        let (r, s) = (b - a, d - c)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        return a + r * t
    }
}
