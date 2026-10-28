import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation

/// A sketch's dimensions as the viewport draws them (ANSI practice, DIM-1): where each kind's geometry lies on the
/// sketch plane, what its text reads and the role it is tinted in. Pure. The viewport lays each one out on screen, so the
/// editor needs no camera.
enum SketchDimensionDrawing {
    /// A dimensioned entity's shape at its solved position.
    enum Shape {
        case point(Vector2)
        case line(Vector2, Vector2)
        case circle(center: Vector2, radius: Double)
        /// `middle` is the polar angle halfway along the arc.
        case arc(center: Vector2, radius: Double, middle: Double)
    }

    // swiftlint:disable function_parameter_count
    /// One `OverlayDimension` for each dimension whose geometry is there. A dimension in a conflict is `.conflicting`, a
    /// reference or wired one `.dimensionReference`, any other `.dimensionDriving`.
    static func dimensions(sketch: Sketch, solution: SketchSolution, plane: Plane, conflicting: Set<DimensionID>,
                           wired: Set<DimensionID>, units: DocumentUnits, style: DimensionStyle) -> [OverlayDimension] {
        sketch.dimensionIDs.compactMap { id in
            guard let dimension = sketch.dimensions[id],
                  let geometry = geometry(of: dimension, sketch: sketch, solution: solution, plane: plane) else { return nil }
            let isReference = !dimension.isDriving || wired.contains(id)
            let value = dimension.isDriving ? dimension.value : solution.measurements[id] ?? dimension.value
            let reading = DimensionReading(value, dimension.kind.quantity, isReference: isReference,
                                           name: dimension.isExposed ? dimension.name : nil)
            let tint: OverlayTint = conflicting.contains(id) ? .conflicting : isReference ? .dimensionReference : .dimensionDriving
            return OverlayDimension(id: overlayID(id), geometry: geometry, text: style.text(reading, units: units), tint: tint)
        }
    }
    // swiftlint:enable function_parameter_count

    /// The dimension's identity in the viewport: "sketch/<n>".
    static func overlayID(_ id: DimensionID) -> OverlayDimensionID {
        OverlayDimensionID("sketch/\(id.rawValue)")
    }

    /// The sketch dimension a viewport ID names, or `nil` for any other (a "feature/…" ID, a malformed one).
    static func dimensionID(from id: OverlayDimensionID) -> DimensionID? {
        guard id.rawValue.hasPrefix("sketch/"), let raw = Int(id.rawValue.dropFirst("sketch/".count)) else { return nil }
        return DimensionID(raw)
    }

    /// Where the dimension lies in world space (`.standoff` placement); `nil` when its geometry is gone, doesn't fit its
    /// kind, or has no length to draw.
    static func geometry(of dimension: SketchDimension, sketch: Sketch, solution: SketchSolution,
                         plane: Plane) -> DimensionGeometry? {
        let shape = { (id: SketchEntityID) in self.shape(of: id, sketch: sketch, solution: solution) }
        switch dimension.kind {
        case .length(let id):
            guard case .line(let a, let b)? = shape(id) else { return nil }
            return linear(a, b, on: plane)
        case .distance(let first, let second):
            switch (shape(first), shape(second)) {
            case (.point(let a)?, .point(let b)?):
                return linear(a, b, on: plane)
            case (.point(let p)?, .line(let a, let b)?), (.line(let a, let b)?, .point(let p)?):
                return linear(p, EditorGeometry.nearest(to: p, onLine: a, b), on: plane)
            default:
                return nil
            }
        case .radius(let id), .diameter(let id):
            return radial(shape(id), on: plane)
        case .angle(let first, let second):
            guard case .line(let a, let b)? = shape(first), case .line(let c, let d)? = shape(second) else { return nil }
            let corner = intersection(a, b, c, d) ?? ((a + b + c + d) * 0.25)
            return .angular(vertex: plane.point(corner), first: plane.point((a + b) * 0.5), second: plane.point((c + d) * 0.5),
                            normal: plane.normal, placement: .standoff)
        }
    }

    /// A plane direction as a world direction.
    private static func world(_ v: Vector2, on plane: Plane) -> Vector3 {
        plane.xAxis * v.x + plane.yAxis * v.y
    }

    /// The length from `from` to `to`, measured along it and drawn on its upward side; `nil` for no length.
    private static func linear(_ from: Vector2, _ to: Vector2, on plane: Plane) -> DimensionGeometry? {
        guard let side = normal(of: to - from) else { return nil }
        return .linear(from: plane.point(from), to: plane.point(to), direction: world(unit(to - from), on: plane),
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
