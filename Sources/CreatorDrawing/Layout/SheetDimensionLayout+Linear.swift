import CreatorGeometry
import Foundation

extension DrawingBuilder {
    fileprivate struct Run {
        var from: Int
        var to: Int
        var level: Double
        var label: Int
    }

    /// Linear, baseline and chain dimensions along the unit direction `d` (R7, R8).
    mutating func linear(
        _ points: [Vector2], direction d: Vector2, kind: DrawingDimensionKind, labels: [DimensionLabel],
        placement: DimensionPlacement
    ) {
        guard points.count >= 2 else { return }
        let n = Vector2(-d.y, d.x)
        let sign: Double = placement.offset < 0 ? -1 : 1
        let runs = linearRuns(points.count, kind: kind, first: Self.dot(points[0], n) + placement.offset, sign: sign)
        // Each feature's extension line reaches the farthest line it serves.
        var reach = [Double?](repeating: nil, count: points.count)
        for run in runs {
            for index in [run.from, run.to] {
                let distance = abs(run.level - Self.dot(points[index], n))
                if let current = reach[index], abs(current - Self.dot(points[index], n)) >= distance { continue }
                reach[index] = run.level
            }
        }
        for (index, level) in reach.enumerated() {
            guard let level else { continue }
            extensionLine(from: points[index], d: d, n: n, level: level, fallback: sign)
        }
        for run in runs {
            let label = labels[Swift.min(run.label, labels.count - 1)]
            dimensionLine(
                feet: (Self.dot(points[run.from], d), Self.dot(points[run.to], d)), level: run.level, d: d, n: n, label: label,
                textShift: placement.textShift)
        }
    }

    /// The dimension lines a series makes: baseline dimensions stack from the first point, a chain shares one line.
    fileprivate func linearRuns(_ count: Int, kind: DrawingDimensionKind, first: Double, sign: Double) -> [Run] {
        switch kind {
        case .baseline:
            return (1..<count).map {
                Run(from: 0, to: $0, level: first + Double($0 - 1) * style.stackSpacing * sign, label: $0 - 1)
            }
        case .chain:
            return (1..<count).map { Run(from: $0 - 1, to: $0, level: first, label: $0 - 1) }
        default:
            return [Run(from: 0, to: 1, level: first, label: 0)]
        }
    }

    private mutating func extensionLine(from p: Vector2, d: Vector2, n: Vector2, level: Double, fallback: Double) {
        let own = Self.dot(p, n)
        let gap = level - own
        let e: Double = abs(gap) < 1e-12 ? fallback : (gap > 0 ? 1 : -1)
        let s = Self.dot(p, d)
        line(d * s + n * (own + e * style.extensionGap), d * s + n * (level + e * style.extensionOvershoot))
    }

    /// One dimension line between the feet at `a` and `b` along `d` (the n-coordinate `level`), with its arrows and label.
    private mutating func dimensionLine(
        feet: (Double, Double), level: Double, d: Vector2, n: Vector2, label: DimensionLabel, textShift: Double?
    ) {
        let (a, b) = feet
        let lo = Swift.min(a, b), hi = Swift.max(a, b)
        let length = hi - lo
        let arrow = style.arrowLength, gap = style.textGap
        let isISO = style.standard == .iso
        let w = width(of: label)
        let extent = isISO ? w : horizontalExtent(w, along: d)
        let textInside = isISO ? w + 2 * gap <= length : extent + 2 * gap + 2 * arrow <= length
        let arrowsInside = length >= 2 * arrow + 1
        let mid = (lo + hi) / 2
        let centre: Double
        if let textShift { centre = mid + textShift } else if textInside { centre = mid } else { centre = hi + gap + arrow + extent / 2 }

        func at(_ s: Double) -> Vector2 { d * s + n * level }
        // The line, as intervals along d.
        var spans: [(Double, Double)] = [(lo, hi)]
        if arrowsInside {
            self.arrow(tip: at(lo), back: d)
            self.arrow(tip: at(hi), back: d * -1)
        } else {
            self.arrow(tip: at(lo), back: d * -1)
            self.arrow(tip: at(hi), back: d)
            spans.append((lo - 2 * arrow, lo - arrow))
            spans.append((hi + arrow, hi + 2 * arrow))
        }
        spans.append((centre - extent / 2, centre + extent / 2))
        var merged = Self.merged(spans)
        let textAngle: Double
        let textPoint: Vector2
        if isISO {
            textAngle = Self.folded(atan2(d.y, d.x))
            let up = Vector2(-sin(textAngle), cos(textAngle))
            textPoint = at(centre) + up * (style.textLift + height / 2)
        } else {
            textAngle = 0
            textPoint = at(centre)
            merged = Self.removing((centre - extent / 2 - gap, centre + extent / 2 + gap), from: merged)
        }
        for span in merged where span.1 - span.0 > 1e-12 { line(at(span.0), at(span.1)) }
        self.label(label, center: textPoint, angle: textAngle)
    }

    /// The union of overlapping or touching intervals, ordered.
    static func merged(_ spans: [(Double, Double)]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, span.0 <= last.1 + 1e-9 {
                result[result.count - 1].1 = Swift.max(last.1, span.1)
            } else {
                result.append(span)
            }
        }
        return result
    }

    static func removing(_ cut: (Double, Double), from spans: [(Double, Double)]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for span in spans {
            if span.1 <= cut.0 || span.0 >= cut.1 {
                result.append(span)
                continue
            }
            if span.0 < cut.0 { result.append((span.0, cut.0)) }
            if span.1 > cut.1 { result.append((cut.1, span.1)) }
        }
        return result
    }

    /// Ordinate dimensions: per feature a leader to the line `x . n = origin . n + offset`, its value at the end (R8).
    mutating func ordinate(
        origin: Vector2, points: [Vector2], direction d: Vector2, labels: [DimensionLabel], placement: DimensionPlacement
    ) {
        let n = Vector2(-d.y, d.x)
        let level = Self.dot(origin, n) + placement.offset
        let features = [origin] + points
        let isISO = style.standard == .iso
        for (index, p) in features.enumerated() {
            let own = Self.dot(p, n)
            let e: Double = level - own >= 0 ? 1 : -1
            let end = p + n * (level - own)
            let start = p + n * (e * style.extensionGap)
            if (end - start).length > 1e-12 || style.extensionGap == 0 { line(start, end) }
            let label = labels[Swift.min(index, labels.count - 1)]
            let w = width(of: label)
            let direction = n * e
            let angle: Double
            let extent: Double
            if isISO {
                angle = Self.folded(atan2(direction.y, direction.x))
                extent = w
            } else {
                angle = 0
                extent = horizontalExtent(w, along: direction)
            }
            let centre = end + direction * (style.textGap + extent / 2)
            self.label(label, center: centre, angle: angle)
        }
    }
}
