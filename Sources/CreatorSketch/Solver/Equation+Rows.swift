import CreatorGeometry
import Foundation

extension Equation {
    /// The residual rows at `x`, each with its analytic gradient.
    func rows(_ x: [Double]) -> [RowBuilder] {
        switch self {
        case .coincident(let p, let q):
            return Self.difference(p, q, x)
        case .pointOnLine(let p, let line):
            return [Self.signedDistance(p, line, x)]
        case .pointOnCircle(let p, let circle):
            var row = Self.distanceRow(p, circle.center, x)
            row.value -= circle.radiusValue(x)
            circle.addRadiusGradient(-1, x, to: &row)
            return [row]
        case .horizontal(let a, let b):
            var row = RowBuilder(value: a.value(x).y - b.value(x).y)
            row.add(a, Vector2(0, 1))
            row.add(b, Vector2(0, -1))
            return [row]
        case .vertical(let a, let b):
            var row = RowBuilder(value: a.value(x).x - b.value(x).x)
            row.add(a, Vector2(1, 0))
            row.add(b, Vector2(-1, 0))
            return [row]
        case .horizontalLine(let line, let scale):
            return [Self.angleRow(Self.directionAngle(line, x), offset: 0, period: .pi, scale: scale)]
        case .verticalLine(let line, let scale):
            return [Self.angleRow(Self.directionAngle(line, x), offset: .pi / 2, period: .pi, scale: scale)]
        case .parallel(let first, let second, let scale):
            return [Self.angleRow(Self.angleBetween(first, second, x), offset: 0, period: .pi, scale: scale)]
        case .perpendicular(let first, let second, let scale):
            return [Self.angleRow(Self.angleBetween(first, second, x), offset: .pi / 2, period: .pi, scale: scale)]
        case .angle(let first, let second, let target, let scale):
            return [Self.angleRow(Self.angleBetween(first, second, x), offset: target, period: 2 * .pi, scale: scale)]
        case .tangentAtPoint(let p, let center, let line):
            return [Self.projection(from: center, to: p, along: line, x)]
        case .lineTangent(let line, let circle, let side):
            var row = Self.signedDistance(circle.center, line, x)
            row.scale(by: side)
            row.value -= circle.radiusValue(x)
            circle.addRadiusGradient(-1, x, to: &row)
            return [row]
        case .circleTangent(let first, let second, let isInternal, let sign):
            var row = Self.distanceRow(first.center, second.center, x)
            if isInternal {
                row.value -= sign * (first.radiusValue(x) - second.radiusValue(x))
                first.addRadiusGradient(-sign, x, to: &row)
                second.addRadiusGradient(sign, x, to: &row)
            } else {
                row.value -= first.radiusValue(x) + second.radiusValue(x)
                first.addRadiusGradient(-1, x, to: &row)
                second.addRadiusGradient(-1, x, to: &row)
            }
            return [row]
        case .equalLength(let first, let second):
            var row = Self.distanceRow(first.end, first.start, x)
            let other = Self.distanceRow(second.end, second.start, x)
            row.value -= other.value
            for entry in other.entries { row.add(column: entry.column, -entry.value) }
            return [row]
        case .equalRadius(let first, let second):
            var row = RowBuilder(value: first.radiusValue(x) - second.radiusValue(x))
            first.addRadiusGradient(1, x, to: &row)
            second.addRadiusGradient(-1, x, to: &row)
            return [row]
        case .midpoint(let p, let line):
            let (a, b, point) = (line.start.value(x), line.end.value(x), p.value(x))
            var rowX = RowBuilder(value: point.x - (a.x + b.x) / 2)
            rowX.add(p, Vector2(1, 0))
            rowX.add(line.start, Vector2(-0.5, 0))
            rowX.add(line.end, Vector2(-0.5, 0))
            var rowY = RowBuilder(value: point.y - (a.y + b.y) / 2)
            rowY.add(p, Vector2(0, 1))
            rowY.add(line.start, Vector2(0, -0.5))
            rowY.add(line.end, Vector2(0, -0.5))
            return [rowX, rowY]
        case .symmetric(let p, let q, let line):
            return [Self.symmetricMidpointRow(p, q, line, x), Self.projection(from: p, to: q, along: line, x)]
        case .fix(let p, let target), .target(let p, let target):
            return Self.difference(p, .constant(target), x)
        case .distance(let p, let q, let value):
            var row = Self.distanceRow(p, q, x)
            row.value -= value
            return [row]
        case .lineDistance(let p, let line, let value, let side):
            var row = Self.signedDistance(p, line, x)
            row.scale(by: side)
            row.value -= value
            return [row]
        case .length(let line, let value):
            var row = Self.distanceRow(line.end, line.start, x)
            row.value -= value
            return [row]
        case .radius(let circle, let value):
            var row = RowBuilder(value: circle.radiusValue(x) - value)
            circle.addRadiusGradient(1, x, to: &row)
            return [row]
        case .arcRadius(let center, let start, let end):
            var row = Self.distanceRow(end, center, x)
            let other = Self.distanceRow(start, center, x)
            row.value -= other.value
            for entry in other.entries { row.add(column: entry.column, -entry.value) }
            return [row]
        }
    }

    /// p − q as two rows.
    static func difference(_ p: PointOperand, _ q: PointOperand, _ x: [Double]) -> [RowBuilder] {
        let delta = p.value(x) - q.value(x)
        var rowX = RowBuilder(value: delta.x)
        rowX.add(p, Vector2(1, 0))
        rowX.add(q, Vector2(-1, 0))
        var rowY = RowBuilder(value: delta.y)
        rowY.add(p, Vector2(0, 1))
        rowY.add(q, Vector2(0, -1))
        return [rowX, rowY]
    }

    /// |p − q|. The gradient is zero where p = q (deterministic, and LM's damping moves on).
    static func distanceRow(_ p: PointOperand, _ q: PointOperand, _ x: [Double]) -> RowBuilder {
        let delta = p.value(x) - q.value(x)
        let length = delta.length
        var row = RowBuilder(value: length)
        guard length > 0 else { return row }
        let unit = delta * (1 / length)
        row.add(p, unit)
        row.add(q, unit * -1)
        return row
    }

    /// cross(d, p − a) / |d| with d = b − a: the signed distance from p to the line (positive on
    /// the left of a → b). A zero-length line counts as the point it shrank to, so collapsing a
    /// line can't satisfy a constraint.
    static func signedDistance(_ p: PointOperand, _ line: LineOperand, _ x: [Double]) -> RowBuilder {
        let (a, point) = (line.start.value(x), p.value(x))
        let d = line.direction(x)
        let w = point - a
        let n = d.length
        guard n > 0 else { return distanceRow(p, line.start, x) }
        let value = SketchMath.cross(d, w) / n
        var row = RowBuilder(value: value)
        let byD = Vector2(w.y, -w.x) * (1 / n) - d * (value / (n * n))
        let byW = Vector2(-d.y, d.x) * (1 / n)
        row.add(p, byW)
        row.add(line.end, byD)
        row.add(line.start, (byD + byW) * -1)
        return row
    }

    /// (q − p) · d / |d|: how far q lies from p along the line's direction.
    static func projection(from p: PointOperand, to q: PointOperand, along line: LineOperand, _ x: [Double]) -> RowBuilder {
        let d = line.direction(x)
        let e = q.value(x) - p.value(x)
        let n = d.length
        guard n > 0 else { return degenerateLine }
        let value = SketchMath.dot(e, d) / n
        var row = RowBuilder(value: value)
        let byE = d * (1 / n)
        let byD = e * (1 / n) - d * (value / (n * n))
        row.add(q, byE)
        row.add(p, byE * -1)
        row.add(line.end, byD)
        row.add(line.start, byD * -1)
        return row
    }

    /// The signed distance from the midpoint of p and q to the line.
    static func symmetricMidpointRow(_ p: PointOperand, _ q: PointOperand, _ line: LineOperand, _ x: [Double]) -> RowBuilder {
        let a = line.start.value(x)
        let d = line.direction(x)
        let m = (p.value(x) + q.value(x)) * 0.5
        let w = m - a
        let n = d.length
        guard n > 0 else {
            // Like signedDistance: a collapsed line is the point it became.
            var row = RowBuilder(value: w.length)
            guard w.length > 0 else { return row }
            let unit = w * (1 / w.length)
            row.add(p, unit * 0.5)
            row.add(q, unit * 0.5)
            row.add(line.start, unit * -1)
            return row
        }
        let value = SketchMath.cross(d, w) / n
        var row = RowBuilder(value: value)
        let byD = Vector2(w.y, -w.x) * (1 / n) - d * (value / (n * n))
        let byW = Vector2(-d.y, d.x) * (1 / n)
        row.add(p, byW * 0.5)
        row.add(q, byW * 0.5)
        row.add(line.end, byD)
        row.add(line.start, (byD + byW) * -1)
        return row
    }

    /// The value of an angle-type residual on a zero-length line: as far from satisfied as a
    /// unit angle, so a solve never "meets" an angle by collapsing a line.
    static let degenerateLine = RowBuilder(value: 1)

    /// scale · (angle − offset), wrapped into [−period/2, period/2]: the angle-type residual.
    ///
    /// The residual is the angle itself, not its sine or cosine, so its gradient never vanishes:
    /// a sine or cosine is stationary where the constraint is furthest from met (horizontal on
    /// an exactly vertical line, perpendicular on exactly parallel lines), and LM would stall
    /// there and report a false conflict. Near zero it equals the old sine form to first order.
    /// The wrap's jump sits at the far point, where the residual is largest. A zero-length line
    /// gives `degenerateLine`.
    static func angleRow(_ angle: RowBuilder?, offset: Double, period: Double, scale: Double) -> RowBuilder {
        guard var row = angle else {
            var degenerate = degenerateLine
            degenerate.scale(by: scale)
            return degenerate
        }
        row.value = (row.value - offset).remainder(dividingBy: period)
        row.scale(by: scale)
        return row
    }

    /// atan2(d.y, d.x), the polar angle of the line's direction, or `nil` for a zero-length line.
    static func directionAngle(_ line: LineOperand, _ x: [Double]) -> RowBuilder? {
        let d = line.direction(x)
        let squared = SketchMath.dot(d, d)
        guard squared > 0 else { return nil }
        var row = RowBuilder(value: atan2(d.y, d.x))
        let byD = Vector2(-d.y, d.x) * (1 / squared)
        row.add(line.end, byD)
        row.add(line.start, byD * -1)
        return row
    }

    /// The signed angle from the first line's direction to the second's, in (−π, π], or `nil`
    /// when either line has zero length.
    static func angleBetween(_ first: LineOperand, _ second: LineOperand, _ x: [Double]) -> RowBuilder? {
        let (d1, d2) = (first.direction(x), second.direction(x))
        let (s1, s2) = (SketchMath.dot(d1, d1), SketchMath.dot(d2, d2))
        guard s1 > 0, s2 > 0 else { return nil }
        var row = RowBuilder(value: atan2(SketchMath.cross(d1, d2), SketchMath.dot(d1, d2)))
        let byD1 = Vector2(d1.y, -d1.x) * (1 / s1)
        let byD2 = Vector2(-d2.y, d2.x) * (1 / s2)
        row.add(first.end, byD1)
        row.add(first.start, byD1 * -1)
        row.add(second.end, byD2)
        row.add(second.start, byD2 * -1)
        return row
    }
}
