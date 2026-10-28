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

    /// The viewport identity of the Dimension tool's pending dimension, which is in no sketch yet.
    static let pendingID = OverlayDimensionID("sketch/new")

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
            let reading = DimensionReading(value, dimension.kind.quantity, count: equalCount(of: dimension.kind, in: sketch),
                                           isReference: isReference, name: dimension.isExposed ? dimension.name : nil)
            let tint: OverlayTint = conflicting.contains(id) ? .conflicting : isReference ? .dimensionReference : .dimensionDriving
            return OverlayDimension(id: overlayID(id), geometry: geometry, text: style.text(reading, units: units), tint: tint)
        }
    }
    // swiftlint:enable function_parameter_count

    /// The pending dimension as the viewport draws it, tinted selected; `nil` when its geometry has no length to draw.
    static func pending(_ pending: PendingDimension, sketch: Sketch, solution: SketchSolution, plane: Plane,
                        units: DocumentUnits, style: DimensionStyle) -> OverlayDimension? {
        let dimension = SketchDimension(kind: pending.kind, name: "", value: pending.value, isDriving: pending.isDriving,
                                        labelPoint: pending.labelPoint)
        guard let geometry = geometry(of: dimension, sketch: sketch, solution: solution, plane: plane) else { return nil }
        let reading = DimensionReading(pending.value, pending.kind.quantity, count: equalCount(of: pending.kind, in: sketch),
                                       isReference: !pending.isDriving)
        return OverlayDimension(id: pendingID, geometry: geometry, text: style.text(reading, units: units), tint: .selected)
    }

    /// The dimension's identity in the viewport: "sketch/<n>".
    static func overlayID(_ id: DimensionID) -> OverlayDimensionID {
        OverlayDimensionID("sketch/\(id.rawValue)")
    }

    /// The sketch dimension a viewport ID names, or `nil` for any other (a "feature/…" ID, a malformed one).
    static func dimensionID(from id: OverlayDimensionID) -> DimensionID? {
        guard id.rawValue.hasPrefix("sketch/"), let raw = Int(id.rawValue.dropFirst("sketch/".count)) else { return nil }
        return DimensionID(raw)
    }

    /// The "NX" of a radius or diameter: how many circles (arcs) are equal to the one measured, when 2 or more.
    private static func equalCount(of kind: DimensionKind, in sketch: Sketch) -> Int? {
        switch kind {
        case .radius(let id), .diameter(let id):
            let count = sketch.equalSet(of: id).count
            return count >= 2 ? count : nil
        default:
            return nil
        }
    }

    /// Where the dimension lies in world space (`.standoff` placement, or `.through` its saved label point); `nil` when its
    /// geometry is gone, doesn't fit its kind, or has no length to draw.
    static func geometry(of dimension: SketchDimension, sketch: Sketch, solution: SketchSolution,
                         plane: Plane) -> DimensionGeometry? {
        let label = dimension.labelPoint
        let shape = { (id: SketchEntityID) in self.shape(of: id, sketch: sketch, solution: solution) }
        switch dimension.kind {
        case .length(let id):
            guard case .line(let a, let b)? = shape(id) else { return nil }
            return linear(a, b, label: label, on: plane)
        case .distance(let first, let second):
            switch (shape(first), shape(second)) {
            case (.point(let a)?, .point(let b)?):
                return linear(a, b, label: label, on: plane)
            case (.point(let p)?, .line(let a, let b)?), (.line(let a, let b)?, .point(let p)?):
                return linear(p, EditorGeometry.nearest(to: p, onLine: a, b), label: label, on: plane)
            default:
                return nil
            }
        case .centreDistance, .horizontalDistance, .verticalDistance, .lineDistance:
            return axisGeometry(of: dimension.kind, label: label, sketch: sketch, solution: solution, plane: plane)
        case .radius(let id), .diameter(let id):
            return radial(shape(id), label: label, on: plane)
        case .angle(let first, let second):
            guard case .line(let a, let b)? = shape(first), case .line(let c, let d)? = shape(second) else { return nil }
            let corner = intersection(a, b, c, d) ?? ((a + b + c + d) * 0.25)
            return .angular(vertex: plane.point(corner), first: plane.point((a + b) * 0.5), second: plane.point((c + d) * 0.5),
                            normal: plane.normal, placement: placement(label, on: plane))
        }
    }

    /// The kinds that measure between centres, along an axis or between lines.
    private static func axisGeometry(of kind: DimensionKind, label: Vector2?, sketch: Sketch, solution: SketchSolution,
                                     plane: Plane) -> DimensionGeometry? {
        let shape = { (id: SketchEntityID) in self.shape(of: id, sketch: sketch, solution: solution) }
        switch kind {
        case .centreDistance(let first, let second):
            guard let a = centre(shape(first)), let b = centre(shape(second)) else { return nil }
            return linear(a, b, label: label, on: plane)
        case .horizontalDistance(let first, let second), .verticalDistance(let first, let second):
            guard let a = centre(shape(first)), let b = centre(shape(second)) else { return nil }
            let isHorizontal = { if case .horizontalDistance = kind { true } else { false } }()
            let middle = (a + b) * 0.5
            var sign = 1.0
            if let label, (isHorizontal ? label.y - middle.y : label.x - middle.x) < 0 { sign = -1 }
            let direction = isHorizontal ? Vector2(1, 0) : Vector2(0, 1)
            let side = isHorizontal ? Vector2(0, sign) : Vector2(sign, 0)
            return .linear(from: plane.point(a), to: plane.point(b), direction: world(direction, on: plane),
                           side: world(side, on: plane), placement: placement(label, on: plane))
        case .lineDistance(let first, let second):
            return lineDistance(shape(first), shape(second), label: label, on: plane)
        default:
            return nil
        }
    }

    /// The distance from the second line's midpoint to the first line, along the first line's normal; `nil` when they coincide.
    private static func lineDistance(_ first: Shape?, _ second: Shape?, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        guard case .line(let a, let b)? = first, case .line(let c, let d)? = second else { return nil }
        let middle = (c + d) * 0.5
        let foot = EditorGeometry.nearest(to: middle, onLine: a, b)
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
    static func centre(_ shape: Shape?) -> Vector2? {
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

    /// A plane direction as a world direction.
    private static func world(_ v: Vector2, on plane: Plane) -> Vector3 {
        plane.xAxis * v.x + plane.yAxis * v.y
    }

    /// The length from `from` to `to`, measured along it and drawn on its upward side; `nil` for no length.
    private static func linear(_ from: Vector2, _ to: Vector2, label: Vector2?, on plane: Plane) -> DimensionGeometry? {
        guard let side = normal(of: to - from) else { return nil }
        return .linear(from: plane.point(from), to: plane.point(to), direction: world(unit(to - from), on: plane),
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
