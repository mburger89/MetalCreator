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
            var row = Self.unitComponent(line, vertical: false, x)
            row.scale(by: scale)
            return [row]
        case .verticalLine(let line, let scale):
            var row = Self.unitComponent(line, vertical: true, x)
            row.scale(by: scale)
            return [row]
        case .parallel(let first, let second, let scale):
            var row = Self.unitCross(first, second, x)
            row.scale(by: scale)
            return [row]
        case .perpendicular(let first, let second, let scale):
            var row = Self.unitDot(first, second, x)
            row.scale(by: scale)
            return [row]
        case .angle(let first, let second, let target, let scale):
            // cos(t) − sin(t) vanishes at 45°, so the per-row fallback would read as satisfied.
            guard first.direction(x).length > 0, second.direction(x).length > 0 else {
                return [RowBuilder(value: scale)]
            }
            let crossRow = Self.unitCross(first, second, x)
            let dotRow = Self.unitDot(first, second, x)
            let (c, s) = (cos(target), sin(target))
            var row = RowBuilder(value: crossRow.value * c - dotRow.value * s)
            for entry in crossRow.entries { row.add(column: entry.column, entry.value * c) }
            for entry in dotRow.entries { row.add(column: entry.column, -entry.value * s) }
            row.scale(by: scale)
            return [row]
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
    /// unit sine or cosine can be, so a solve never "meets" an angle by collapsing a line.
    static let degenerateLine = RowBuilder(value: 1)

    /// d.y / |d| (or d.x / |d| when `vertical`): the sine (cosine) of the line's angle to the x axis.
    static func unitComponent(_ line: LineOperand, vertical: Bool, _ x: [Double]) -> RowBuilder {
        let d = line.direction(x)
        let n = d.length
        guard n > 0 else { return degenerateLine }
        let cube = n * n * n
        var row = RowBuilder(value: (vertical ? d.x : d.y) / n)
        let byD = vertical ? Vector2(d.y * d.y, -d.x * d.y) * (1 / cube) : Vector2(-d.x * d.y, d.x * d.x) * (1 / cube)
        row.add(line.end, byD)
        row.add(line.start, byD * -1)
        return row
    }

    /// cross(d₁, d₂) / (|d₁| |d₂|): the sine of the angle from the first line to the second.
    static func unitCross(_ first: LineOperand, _ second: LineOperand, _ x: [Double]) -> RowBuilder {
        let (d1, d2) = (first.direction(x), second.direction(x))
        let (n1, n2) = (d1.length, d2.length)
        guard n1 > 0, n2 > 0 else { return degenerateLine }
        let value = SketchMath.cross(d1, d2) / (n1 * n2)
        var row = RowBuilder(value: value)
        let byD1 = Vector2(d2.y, -d2.x) * (1 / (n1 * n2)) - d1 * (value / (n1 * n1))
        let byD2 = Vector2(-d1.y, d1.x) * (1 / (n1 * n2)) - d2 * (value / (n2 * n2))
        row.add(first.end, byD1)
        row.add(first.start, byD1 * -1)
        row.add(second.end, byD2)
        row.add(second.start, byD2 * -1)
        return row
    }

    /// d₁ · d₂ / (|d₁| |d₂|): the cosine of the angle between the lines.
    static func unitDot(_ first: LineOperand, _ second: LineOperand, _ x: [Double]) -> RowBuilder {
        let (d1, d2) = (first.direction(x), second.direction(x))
        let (n1, n2) = (d1.length, d2.length)
        guard n1 > 0, n2 > 0 else { return degenerateLine }
        let value = SketchMath.dot(d1, d2) / (n1 * n2)
        var row = RowBuilder(value: value)
        let byD1 = d2 * (1 / (n1 * n2)) - d1 * (value / (n1 * n1))
        let byD2 = d1 * (1 / (n1 * n2)) - d2 * (value / (n2 * n2))
        row.add(first.end, byD1)
        row.add(first.start, byD1 * -1)
        row.add(second.end, byD2)
        row.add(second.start, byD2 * -1)
        return row
    }
}
