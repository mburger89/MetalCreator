import CreatorGeometry
import Foundation

extension DimensionInference {
    /// Where the placing click (sheet millimetres) puts a dimension relative to what it measures (plan R7): the click's distance
    /// along n from the first feature point, or its direction and distance about the centre or vertex.
    public static func placement(
        for kind: DrawingDimensionKind, picks: [PickedAnchor], placing: Vector2, mapping: ViewMapping
    ) -> DimensionPlacement {
        switch kind {
        case .linear(let direction), .baseline(let direction), .chain(let direction):
            return linear(direction, picks: picks, placing: placing, mapping: mapping)
        case .ordinate(let axis):
            let d = axis == .horizontal ? Vector2(1, 0) : Vector2(0, 1)
            let click = mapping.model(placing)
            let origin = picks.first.map { firstPoint($0, along: d, click: click) } ?? .zero
            return DimensionPlacement(offset: dot(placing - mapping.sheet(origin), turned(d)), angle: 0)
        case .radius, .diameter: return radial(picks: picks, placing: placing, mapping: mapping)
        case .angle: return angle(picks: picks, placing: placing, mapping: mapping)
        case .chamfer:
            guard case .line(let a, let b)? = picks.first.map(feature) else { return DimensionPlacement(offset: 0, angle: 0) }
            return about(mapping.sheet((a + b) * 0.5), placing: placing, minus: 0)
        }
    }

    /// The click's direction and distance about `centre`, less `radius` (sheet millimetres).
    private static func about(_ centre: Vector2, placing: Vector2, minus radius: Double) -> DimensionPlacement {
        let v = placing - centre
        return DimensionPlacement(offset: v.length - radius, angle: atan2(v.y, v.x))
    }

    private static func radial(picks: [PickedAnchor], placing: Vector2, mapping: ViewMapping) -> DimensionPlacement {
        guard let pick = picks.first else { return DimensionPlacement(offset: 0, angle: 0) }
        switch pick.shape {
        case .circle(let center, let radius, _):
            return about(mapping.sheet(center), placing: placing, minus: radius * mapping.scale)
        case .cylinder:
            return linear(.aligned, picks: picks, placing: placing, mapping: mapping)
        default: return DimensionPlacement(offset: 0, angle: 0)
        }
    }

    private static func angle(picks: [PickedAnchor], placing: Vector2, mapping: ViewMapping) -> DimensionPlacement {
        guard picks.count == 2, case .line(let a, let b) = feature(picks[0]), case .line(let c, let d) = feature(picks[1]) else {
            return DimensionPlacement(offset: 0, angle: 0)
        }
        var vertex = (a + b) * 0.5
        if let u = unit(b - a), let v = unit(d - c) {
            let denominator = u.x * v.y - u.y * v.x
            if abs(denominator) > 1e-9 {
                let gap = c - a
                vertex = a + u * ((gap.x * v.y - gap.y * v.x) / denominator)
            }
        }
        return about(mapping.sheet(vertex), placing: placing, minus: 0)
    }

    // MARK: Linear

    private static func linear(
        _ direction: LinearDirection, picks: [PickedAnchor], placing: Vector2, mapping: ViewMapping
    ) -> DimensionPlacement {
        let click = mapping.model(placing)
        guard let (d, a) = basis(direction, picks: picks, click: click) else { return DimensionPlacement(offset: 0, angle: 0) }
        return DimensionPlacement(offset: dot(placing - mapping.sheet(a), turned(d)), angle: 0)
    }

    /// The measuring direction and the first feature point, as the measure finds them.
    private static func basis(_ direction: LinearDirection, picks: [PickedAnchor], click: Vector2) -> (Vector2, Vector2)? {
        if let first = picks.first, picks.count == 1, case .cylinder(let axisPoint, let axis, let radius) = first.shape {
            let d = turned(axis)
            return (d, axisPoint - d * radius)
        }
        switch direction {
        case .horizontal, .vertical:
            let d = direction == .horizontal ? Vector2(1, 0) : Vector2(0, 1)
            if picks.count == 1, case .line(let start, _) = feature(picks[0]) { return (d, start) }
            return picks.first.map { (d, firstPoint($0, along: d, click: click)) }
        case .aligned: return alignedBasis(picks, click: click)
        }
    }

    private static func alignedBasis(_ picks: [PickedAnchor], click: Vector2) -> (Vector2, Vector2)? {
        let features = picks.map(feature)
        if features.count == 1, case .line(let a, let b) = features[0], let d = unit(b - a) { return (d, a) }
        guard features.count == 2 else { return nil }
        switch (features[0], features[1]) {
        case (.point(let p), .point(let q)): return unit(q - p).map { ($0, p) }
        case (.point(let p), .line(let a, let b)): return pointToLine(p, a, b, pointFirst: true)
        case (.line(let a, let b), .point(let p)): return pointToLine(p, a, b, pointFirst: false)
        case (.line(let a, let b), .line(let c, _)):
            guard let along = unit(b - a) else { return nil }
            var normal = turned(along)
            if dot(c - a, normal) < 0 { normal = Vector2(-normal.x, -normal.y) }
            return (normal, nearerEnd(a, b, along: turned(normal), click: click))
        }
    }

    /// The perpendicular from a point to a line: from the point to its foot, or from the foot to the point.
    private static func pointToLine(_ p: Vector2, _ a: Vector2, _ b: Vector2, pointFirst: Bool) -> (Vector2, Vector2)? {
        guard let along = unit(b - a) else { return nil }
        let foot = a + along * dot(p - a, along)
        if pointFirst { return (unit(foot - p) ?? turned(along), p) }
        return (unit(p - foot) ?? turned(along), foot)
    }

    /// A feature's point for a dimension that measures along `d`: a line gives its end nearer the click across `d`.
    private static func firstPoint(_ pick: PickedAnchor, along d: Vector2, click: Vector2) -> Vector2 {
        switch feature(pick) {
        case .point(let p): return p
        case .line(let a, let b): return nearerEnd(a, b, along: turned(d), click: click)
        }
    }

    /// The end of a line that the dimension line, which lies at `click`, is nearer when measured along `n`: the end with the
    /// larger n coordinate unless the click is below both.
    private static func nearerEnd(_ a: Vector2, _ b: Vector2, along n: Vector2, click: Vector2) -> Vector2 {
        let (high, low) = dot(a, n) >= dot(b, n) ? (a, b) : (b, a)
        return dot(click, n) <= dot(low, n) ? low : high
    }
}
