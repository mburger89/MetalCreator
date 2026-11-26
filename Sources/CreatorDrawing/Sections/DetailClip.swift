import CreatorGeometry
import CreatorKernel
import Foundation

/// R8's detail clip: a parent's projection cut to a circle in the model plane. Lines stay lines, arcs arcs, ellipses elliptic arcs and
/// polylines polylines; a piece is kept when its middle is inside or on the circle and dropped when under `minimumLength`.
public enum DetailClip {
    public static let parentDeletedSentence = "The view this detail enlarged was deleted."

    /// Pieces shorter than this (millimetres in the model plane) are dropped.
    static let minimumLength = 1e-9
    /// Tolerance for "inside or on" the circle.
    static let onCircle = 1e-9
    private static let bisectionStop = 1e-12

    /// `projection` cut to `circle`: visibility, class and source kept per piece, input order kept, pieces in curve order.
    public static func clip(_ projection: Projection2D, to circle: HatchClip) -> Projection2D {
        var lines: [ProjectedLine] = []
        for line in projection.lines {
            for curve in pieces(of: line.curve, circle: circle) {
                lines.append(
                    ProjectedLine(visibility: line.visibility, lineClass: line.lineClass, curve: curve, source: line.source))
            }
        }
        return Projection2D(lines: lines)
    }

    /// A detail's content from its parent's (R8).
    public static func content(of parent: ViewContent?, circle: DetailCircle) -> ViewContent {
        guard let parent else { return ViewContent(problem: parentDeletedSentence) }
        let cut = HatchClip(center: circle.center, radius: circle.radius)
        let square = Rect2D(
            min: Vector2(circle.center.x - circle.radius, circle.center.y - circle.radius),
            max: Vector2(circle.center.x + circle.radius, circle.center.y + circle.radius))
        return ViewContent(
            projection: parent.projection.map { Self.clip($0, to: cut) }, topology: parent.topology, isPending: parent.isPending,
            problem: parent.problem, warnings: parent.warnings, lastSize: nil, hatch: parent.hatch,
            hatchClips: parent.hatchClips + [cut], framing: square)
    }

    // MARK: Pieces

    private static func pieces(of curve: ProjectedCurve, circle: HatchClip) -> [ProjectedCurve] {
        switch curve {
        case .line(let a, let b): linePieces(a, b, circle)
        case .arc(let center, let radius, let start, let sweep): arcPieces(center, radius, start, sweep, circle)
        case .ellipse(let center, let axis, let major, let minor, let start, let sweep):
            ellipsePieces(Ellipse(center: center, axis: axis, major: major, minor: minor, start: start, sweep: sweep), circle)
        case .polyline(let points): polylinePieces(points, circle)
        }
    }

    private static func isInside(_ p: Vector2, _ circle: HatchClip) -> Bool {
        (p - circle.center).length <= circle.radius + onCircle
    }

    /// The parameters in (0, 1) where the segment crosses the circle, ascending.
    private static func crossings(_ a: Vector2, _ b: Vector2, _ circle: HatchClip) -> [Double] {
        let d = b - a, f = a - circle.center
        let qa = d.x * d.x + d.y * d.y
        guard qa > 0 else { return [] }
        let qb = 2 * (d.x * f.x + d.y * f.y)
        let qc = f.x * f.x + f.y * f.y - circle.radius * circle.radius
        let disc = qb * qb - 4 * qa * qc
        guard disc > 0 else { return [] }
        let root = disc.squareRoot()
        return [(-qb - root) / (2 * qa), (-qb + root) / (2 * qa)].filter { $0 > 0 && $0 < 1 }
    }

    private static func lerp(_ a: Vector2, _ b: Vector2, _ t: Double) -> Vector2 {
        t == 0 ? a : (t == 1 ? b : Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
    }

    private static func linePieces(_ a: Vector2, _ b: Vector2, _ circle: HatchClip) -> [ProjectedCurve] {
        let cuts = [0.0] + crossings(a, b, circle) + [1.0]
        var result: [ProjectedCurve] = []
        for index in 0..<(cuts.count - 1) {
            let p = lerp(a, b, cuts[index]), q = lerp(a, b, cuts[index + 1])
            guard (q - p).length >= minimumLength, isInside(lerp(a, b, (cuts[index] + cuts[index + 1]) / 2), circle) else { continue }
            result.append(.line(p, q))
        }
        return result
    }

    private static func polylinePieces(_ points: [Vector2], _ circle: HatchClip) -> [ProjectedCurve] {
        guard points.count >= 2 else { return [] }
        var runs: [[Vector2]] = []
        var run: [Vector2] = []
        func flush() {
            if run.count >= 2, (1..<run.count).reduce(0, { $0 + (run[$1] - run[$1 - 1]).length }) >= minimumLength {
                runs.append(run)
            }
            run = []
        }
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let cuts = [0.0] + crossings(a, b, circle) + [1.0]
            for k in 0..<(cuts.count - 1) {
                let p = lerp(a, b, cuts[k]), q = lerp(a, b, cuts[k + 1])
                guard isInside(lerp(a, b, (cuts[k] + cuts[k + 1]) / 2), circle) else {
                    flush()
                    continue
                }
                if run.last != p { flush(); run = [p] }
                run.append(q)
            }
        }
        flush()
        return runs.map { .polyline($0) }
    }

    /// Cut offsets `0 ... span` at `interior` (ascending, strictly inside) and keep the spans whose middle `isKept`.
    private static func spans(_ span: Double, _ interior: [Double], keep isKept: (Double) -> Bool) -> [(Double, Double)] {
        var cuts = [0.0]
        for value in interior.sorted() where value > cuts[cuts.count - 1] + 1e-15 && value < span { cuts.append(value) }
        cuts.append(span)
        var kept: [(Double, Double)] = []
        for index in 0..<(cuts.count - 1) {
            let low: Double = cuts[index], high: Double = cuts[index + 1]
            if isKept((low + high) / 2) { kept.append((low, high)) }
        }
        return kept
    }

    private static func arcPieces(
        _ center: Vector2, _ radius: Double, _ start: Double, _ sweep: Double, _ circle: HatchClip
    ) -> [ProjectedCurve] {
        let sign: Double = sweep < 0 ? -1 : 1
        let span = abs(sweep)
        func point(_ offset: Double) -> Vector2 {
            let t = start + sign * offset
            return Vector2(center.x + radius * cos(t), center.y + radius * sin(t))
        }
        var cuts: [Double] = []
        let between = circle.center - center
        let distance = between.length
        if distance > 0, radius > 0 {
            let cosine = (radius * radius + distance * distance - circle.radius * circle.radius) / (2 * radius * distance)
            if abs(cosine) < 1 {
                let spread = acos(cosine), toward = atan2(between.y, between.x)
                for angle in [toward - spread, toward + spread] {
                    var offset = sign * (angle - start)
                    offset = offset.truncatingRemainder(dividingBy: 2 * Double.pi)
                    if offset < 0 { offset += 2 * Double.pi }
                    if offset > 0 && offset < span { cuts.append(offset) }
                }
            }
        }
        return spans(span, cuts) { isInside(point($0), circle) }.compactMap { low, high in
            guard (high - low) * radius >= minimumLength else { return nil }
            if low == 0 && high == span { return .arc(center: center, radius: radius, start: start, sweep: sweep) }
            return .arc(center: center, radius: radius, start: start + sign * low, sweep: sign * (high - low))
        }
    }

    private struct Ellipse {
        var center: Vector2, axis: Vector2
        var major: Double, minor: Double, start: Double, sweep: Double
    }

    private static func ellipsePieces(_ ellipse: Ellipse, _ circle: HatchClip) -> [ProjectedCurve] {
        let (center, axis, major, minor, start, sweep) = (
            ellipse.center, ellipse.axis, ellipse.major, ellipse.minor, ellipse.start, ellipse.sweep)
        let sign: Double = sweep < 0 ? -1 : 1
        let span = abs(sweep)
        let cross = Vector2(-axis.y, axis.x)
        func point(_ offset: Double) -> Vector2 {
            let t = start + sign * offset
            let u = major * cos(t), v = minor * sin(t)
            return Vector2(center.x + u * axis.x + v * cross.x, center.y + u * axis.y + v * cross.y)
        }
        func gap(_ offset: Double) -> Double { (point(offset) - circle.center).length - circle.radius }
        let steps = max(16, Int((256 * span / (2 * Double.pi)).rounded(.up)))
        var cuts: [Double] = []
        var previous = gap(0)
        for step in 1...steps {
            let high = span * Double(step) / Double(steps), low = span * Double(step - 1) / Double(steps)
            let value = gap(high)
            if previous * value < 0 {
                var lo = low, hi = high, loValue = previous
                while hi - lo > bisectionStop {
                    let mid = (lo + hi) / 2, midValue = gap(mid)
                    if loValue * midValue <= 0 { hi = mid } else { lo = mid; loValue = midValue }
                }
                cuts.append((lo + hi) / 2)
            } else if value == 0 && step < steps {
                cuts.append(high)
            }
            previous = value
        }
        return spans(span, cuts) { isInside(point($0), circle) }.compactMap { low, high in
            guard (high - low) * max(major, minor) >= minimumLength else { return nil }
            if low == 0 && high == span {
                return .ellipse(center: center, majorAxis: axis, majorRadius: major, minorRadius: minor, start: start, sweep: sweep)
            }
            return .ellipse(
                center: center, majorAxis: axis, majorRadius: major, minorRadius: minor, start: start + sign * low,
                sweep: sign * (high - low))
        }
    }
}
