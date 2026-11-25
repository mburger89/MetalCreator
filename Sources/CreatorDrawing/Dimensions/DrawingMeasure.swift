import CreatorGeometry
import CreatorKernel
import Foundation

/// What a dimension reads off its anchors: the numbers and the figure the layout draws (model-plane millimetres).
public struct DrawingMeasurement: Hashable, Sendable {
    public var values: [Double]
    public var figure: AnnotationFigure

    public init(values: [Double], figure: AnnotationFigure) {
        self.values = values
        self.figure = figure
    }
}

/// Plan R5 and R6: measures from the model's exact geometry, projected by the view's frame, never a number that would be
/// foreshortened. Views never rotate, so `mapping` changes no direction here and the model-plane directions are the sheet's.
public enum DrawingMeasure {
    public static func measure(
        _ dimension: DrawingDimension, anchors: [AnchorResolution], frame: ProjectionFrame, mapping: ViewMapping?
    ) -> Result<DrawingMeasurement, LostReason> {
        var geometries: [AnchorGeometry] = []
        for anchor in anchors {
            switch anchor {
            case .lost(let reason): return .failure(reason)
            case .held(let geometry, _, _): geometries.append(geometry)
            }
        }
        let context = MeasureContext(frame: frame, offset: dimension.placement.offset, angle: dimension.placement.angle)
        return context.measure(dimension.kind, geometries)
    }
}

private struct MeasureContext {
    let frame: ProjectionFrame
    let offset: Double
    let angle: Double
    private let tolerance = 1e-9

    typealias Outcome = Result<DrawingMeasurement, LostReason>

    func measure(_ kind: DrawingDimensionKind, _ geometries: [AnchorGeometry]) -> Outcome {
        switch kind {
        case .linear(let direction): linear(direction, geometries)
        case .baseline(let direction): series(direction, geometries, chained: false)
        case .chain(let direction): series(direction, geometries, chained: true)
        case .ordinate(let axis): ordinate(axis, geometries)
        case .radius: radial(geometries, isDiameter: false)
        case .diameter: radial(geometries, isDiameter: true)
        case .angle: angle(geometries)
        case .chamfer: chamfer(geometries)
        }
    }

    func success(_ values: [Double], _ figure: AnnotationFigure) -> Outcome {
        .success(DrawingMeasurement(values: values, figure: figure))
    }

    // MARK: Geometry

    /// A segment's ends on the sheet, refused when the segment isn't square to the view (R5).
    func line(_ a: Vector3, _ b: Vector3) -> Result<(Vector2, Vector2), LostReason> {
        let along = b - a
        guard abs(along.dot(frame.direction)) <= tolerance * along.length else { return .failure(.foreshortened) }
        return .success((frame.place(a), frame.place(b)))
    }

    /// The outline's direction across the axis, the model vector `axis x viewDirection`.
    func across(_ axis: Vector3) -> Vector3 { (axis.cross(frame.direction)).normalized ?? Vector3(0, 0, 0) }

    func circleFaceOn(_ axis: Vector3) -> Bool { abs(axis.dot(frame.direction)) >= 1 - tolerance }

    func cylinderSeenSideOn(_ axis: Vector3) -> Bool { abs(axis.dot(frame.direction)) <= tolerance }

    /// What a geometry contributes as a point to a dimension that measures along `direction`: a line gives its end nearer
    /// the dimension line (the side `offset` points to).
    func point(of geometry: AnchorGeometry, along direction: Vector2) -> Result<Vector2, LostReason> {
        switch geometry {
        case .point(let p): return .success(frame.place(p))
        case .circle(let center, let axis, _, _):
            guard circleFaceOn(axis) else { return .failure(.foreshortened) }
            return .success(frame.place(center))
        case .segment(let a, let b):
            switch line(a, b) {
            case .failure(let reason): return .failure(reason)
            case .success(let (p, q)):
                let normal = Vector2(-direction.y, direction.x)
                let towards = offset >= 0
                let pick = (dot(q, normal) > dot(p, normal)) == towards ? q : p
                return .success(pick)
            }
        case .cylinder(let axisPoint, let axis, let radius, let side):
            guard cylinderSeenSideOn(axis) else { return .failure(.foreshortened) }
            return .success(frame.place(axisPoint + across(axis) * (radius * side)))
        case .other: return .failure(.notLineOrCircle)
        }
    }

    // MARK: Linear

    func linear(_ kind: LinearDirection, _ geometries: [AnchorGeometry]) -> Outcome {
        switch (kind, geometries.count) {
        case (.aligned, 1): return singleLine(geometries[0], along: nil)
        case (.aligned, 2): return aligned(geometries[0], geometries[1])
        case (.horizontal, 1), (.vertical, 1): return singleLine(geometries[0], along: direction(of: kind))
        case (.horizontal, 2), (.vertical, 2):
            let d = direction(of: kind)
            return twoPoints(geometries, d)
        default: return .failure(.notLineOrCircle)
        }
    }

    func direction(of kind: LinearDirection) -> Vector2 {
        kind == .vertical ? Vector2(0, 1) : Vector2(1, 0)
    }

    func twoPoints(_ geometries: [AnchorGeometry], _ d: Vector2) -> Outcome {
        var points: [Vector2] = []
        for geometry in geometries {
            switch point(of: geometry, along: d) {
            case .failure(let reason): return .failure(reason)
            case .success(let p): points.append(p)
            }
        }
        return success([abs(dot(points[1] - points[0], d))], .linear(points: points, direction: d))
    }

    func singleLine(_ geometry: AnchorGeometry, along d: Vector2?) -> Outcome {
        guard case .segment(let a, let b) = geometry else { return .failure(.notLineOrCircle) }
        switch line(a, b) {
        case .failure(let reason): return .failure(reason)
        case .success(let (p, q)):
            let along = q - p
            guard let unit = d ?? normalised(along) else { return .failure(.notLineOrCircle) }
            return success([abs(dot(along, unit))], .linear(points: [p, q], direction: unit))
        }
    }

    func aligned(_ first: AnchorGeometry, _ second: AnchorGeometry) -> Outcome {
        switch (first, second) {
        case (.segment(let a, let b), .segment(let c, let d)): return parallel((a, b), (c, d))
        case (.segment(let a, let b), _): return pointAndLine(second, (a, b), lineFirst: true)
        case (_, .segment(let a, let b)): return pointAndLine(first, (a, b), lineFirst: false)
        default:
            let ends = [first, second].map(plainPoint)
            for end in ends { if case .failure(let reason) = end { return .failure(reason) } }
            guard case .success(let p) = ends[0], case .success(let q) = ends[1] else { return .failure(.notLineOrCircle) }
            // The 3D segment between the two points must be square to the view.
            let along = q - p
            guard abs(along.dot(frame.direction)) <= tolerance * along.length else { return .failure(.foreshortened) }
            let (a, b) = (frame.place(p), frame.place(q))
            guard let unit = normalised(b - a) else { return .failure(.notLineOrCircle) }
            return success([(b - a).length], .linear(points: [a, b], direction: unit))
        }
    }

    func plainPoint(_ geometry: AnchorGeometry) -> Result<Vector3, LostReason> {
        switch geometry {
        case .point(let p): return .success(p)
        case .circle(let center, let axis, _, _):
            return circleFaceOn(axis) ? .success(center) : .failure(.foreshortened)
        default: return .failure(.notLineOrCircle)
        }
    }

    func pointAndLine(_ other: AnchorGeometry, _ segment: (Vector3, Vector3), lineFirst: Bool) -> Outcome {
        let p3: Vector3
        switch plainPoint(other) {
        case .failure(let reason): return .failure(reason)
        case .success(let p): p3 = p
        }
        switch line(segment.0, segment.1) {
        case .failure(let reason): return .failure(reason)
        case .success(let (a, b)):
            let p = frame.place(p3)
            guard let along = normalised(b - a) else { return .failure(.notLineOrCircle) }
            let foot = a + along * dot(p - a, along)
            guard let unit = normalised(foot - p) else { return .failure(.notLineOrCircle) }
            return success(
                [(foot - p).length],
                .linear(points: lineFirst ? [foot, p] : [p, foot], direction: lineFirst ? Vector2(-unit.x, -unit.y) : unit))
        }
    }

    func parallel(_ first: (Vector3, Vector3), _ second: (Vector3, Vector3)) -> Outcome {
        switch (line(first.0, first.1), line(second.0, second.1)) {
        case (.failure(let reason), _), (_, .failure(let reason)): return .failure(reason)
        case (.success(let (a, b)), .success(let (c, d))):
            guard let u = normalised(b - a), let v = normalised(d - c), abs(u.x * v.y - u.y * v.x) <= tolerance else {
                return .failure(.notLineOrCircle)
            }
            // The measuring direction runs from the first line towards the second.
            var normal = Vector2(-u.y, u.x)
            if dot(c - a, normal) < 0 { normal = Vector2(-normal.x, -normal.y) }
            let along = Vector2(-normal.y, normal.x)
            let towards = offset >= 0
            let end = (dot(b, along) > dot(a, along)) == towards ? b : a
            let foot = c + v * dot(end - c, v)
            return success([abs(dot(foot - end, normal))], .linear(points: [end, foot], direction: normal))
        }
    }

    // MARK: Series

    func series(_ kind: LinearDirection, _ geometries: [AnchorGeometry], chained: Bool) -> Outcome {
        guard kind != .aligned, geometries.count >= 2 else { return .failure(.notLineOrCircle) }
        let d = direction(of: kind)
        var points: [Vector2] = []
        for geometry in geometries {
            switch point(of: geometry, along: d) {
            case .failure(let reason): return .failure(reason)
            case .success(let p): points.append(p)
            }
        }
        let values = points.indices.dropFirst().map { abs(dot(points[$0] - points[chained ? $0 - 1 : 0], d)) }
        return success(values, .linear(points: points, direction: d))
    }

    func ordinate(_ axis: OrdinateAxis, _ geometries: [AnchorGeometry]) -> Outcome {
        guard geometries.count >= 2 else { return .failure(.notLineOrCircle) }
        let d = axis == .horizontal ? Vector2(1, 0) : Vector2(0, 1)
        var points: [Vector2] = []
        for geometry in geometries {
            switch point(of: geometry, along: d) {
            case .failure(let reason): return .failure(reason)
            case .success(let p): points.append(p)
            }
        }
        let origin = points[0]
        let rest = Array(points.dropFirst())
        return success(rest.map { dot($0 - origin, d) }, .ordinate(origin: origin, points: rest, direction: d))
    }

    // MARK: Circles

    func radial(_ geometries: [AnchorGeometry], isDiameter: Bool) -> Outcome {
        guard geometries.count == 1 else { return .failure(.notLineOrCircle) }
        switch geometries[0] {
        case .circle(let center, let axis, let radius, _):
            guard abs(axis.dot(frame.direction)) >= 1 - tolerance else { return .failure(.foreshortened) }
            let figure = AnnotationFigure.radial(center: frame.place(center), radius: radius, isDiameter: isDiameter)
            return success([isDiameter ? 2 * radius : radius], figure)
        case .cylinder(let axisPoint, let axis, let radius, let side) where isDiameter && side == 0:
            guard cylinderSeenSideOn(axis) else { return .failure(.foreshortened) }
            let n = across(axis)
            let a = frame.place(axisPoint - n * radius)
            let b = frame.place(axisPoint + n * radius)
            guard let unit = normalised(b - a) else { return .failure(.notLineOrCircle) }
            return success([2 * radius], .linear(points: [a, b], direction: unit))
        default: return .failure(.notLineOrCircle)
        }
    }

    // MARK: Angles

    func angle(_ geometries: [AnchorGeometry]) -> Outcome {
        guard geometries.count == 2, case .segment(let a1, let b1) = geometries[0], case .segment(let a2, let b2) = geometries[1] else {
            return .failure(.notLineOrCircle)
        }
        guard line(a1, b1).isSuccess, line(a2, b2).isSuccess else { return .failure(.foreshortened) }
        let (p1, q1, p2, q2) = (frame.place(a1), frame.place(b1), frame.place(a2), frame.place(b2))
        guard let u1 = normalised(q1 - p1), let u2 = normalised(q2 - p2) else { return .failure(.notLineOrCircle) }
        let denominator = u1.x * u2.y - u1.y * u2.x
        guard abs(denominator) > tolerance else { return .failure(.notLineOrCircle) }
        let gap = p2 - p1
        let t = (gap.x * u2.y - gap.y * u2.x) / denominator
        let vertex = p1 + u1 * t
        let rays = [u1, Vector2(-u1.x, -u1.y), u2, Vector2(-u2.x, -u2.y)].map { Self.turn(atan2($0.y, $0.x)) }.sorted()
        let at = Self.turn(angle)
        var width = rays[0] + 2 * .pi - rays[3]
        for index in 0..<3 where at >= rays[index] && at < rays[index + 1] { width = rays[index + 1] - rays[index] }
        return success([width], .angle(vertex: vertex, first: [p1, q1], second: [p2, q2]))
    }

    static func turn(_ angle: Double) -> Double {
        let full = 2 * Double.pi
        let r = angle.truncatingRemainder(dividingBy: full)
        return r < 0 ? r + full : r
    }

    // MARK: Chamfers

    func chamfer(_ geometries: [AnchorGeometry]) -> Outcome {
        guard geometries.count == 2, case .segment(let a1, let b1) = geometries[0], case .segment(let a2, let b2) = geometries[1] else {
            return .failure(.notLineOrCircle)
        }
        guard line(a1, b1).isSuccess, line(a2, b2).isSuccess else { return .failure(.foreshortened) }
        let (p, q) = (frame.place(a1), frame.place(b1))
        guard let u = normalised(q - p), let r = normalised(frame.place(b2) - frame.place(a2)) else {
            return .failure(.notLineOrCircle)
        }
        let cosine = min(1, abs(dot(u, r)))
        return success([(q - p).length * cosine, acos(cosine)], .chamfer(start: p, end: q))
    }

    // MARK: Vector helpers

    func dot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x + a.y * b.y }

    func normalised(_ v: Vector2) -> Vector2? {
        let length = v.length
        return length > 1e-12 ? v * (1 / length) : nil
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
}
