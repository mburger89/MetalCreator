import CreatorGeometry
import Foundation

extension DrawingBuilder {
    private static func turn(_ angle: Double) -> Double {
        let full = 2 * Double.pi
        let r = angle.truncatingRemainder(dividingBy: full)
        return r < 0 ? r + full : r
    }

    /// The angle between two lines: an arc of radius `offset` about the vertex across the sector `placement.angle` picks (R8).
    mutating func angle(vertex: Vector2, first: [Vector2], second: [Vector2], label: DimensionLabel, placement: DimensionPlacement) {
        guard first.count == 2, second.count == 2 else { return }
        func unit(_ points: [Vector2]) -> Vector2? {
            let v = points[1] - points[0]
            let length = v.length
            return length > 1e-12 ? v * (1 / length) : nil
        }
        guard let u1 = unit(first), let u2 = unit(second) else { return }
        let sector = Self.sector(u1, u2, containing: placement.angle)
        let (low, high, sweep) = (sector.low, sector.high, sector.sweep)
        let radius = Swift.max(placement.offset, 0)
        let start = low.0
        let end = start + sweep
        let arrow = style.arrowLength
        let arrowsInside = radius * sweep >= 2 * arrow + 1
        let isISO = style.standard == .iso
        extensionLines(vertex: vertex, radius: radius, rays: [(low.1, first), (high.1, first), (low.1, second), (high.1, second)])

        func onArc(_ a: Double) -> Vector2 { vertex + Self.direction(a) * radius }
        func tangent(_ a: Double) -> Vector2 { Vector2(-sin(a), cos(a)) }
        // Heads: inside, each points out of the arc at its end; outside, each sits beyond the end pointing in.
        let startBack = tangent(start) * (arrowsInside ? 1 : -1)
        let endBack = tangent(end) * (arrowsInside ? -1 : 1)
        self.arrow(tip: onArc(start), back: startBack)
        self.arrow(tip: onArc(end), back: endBack)

        let middle = start + sweep / 2
        let w = width(of: label)
        let point = onArc(middle)
        var pieces: [(Double, Double)] = [(start, end)]
        if !arrowsInside {
            let tail = arrow / Swift.max(radius, 1e-9)
            pieces = [(start, end), (start - 2 * tail, start - tail), (end + tail, end + 2 * tail)]
        }
        if isISO {
            let angle = Self.folded(middle + .pi / 2)
            let up = Vector2(-sin(angle), cos(angle))
            emit(pieces, vertex: vertex, radius: radius)
            self.label(label, center: point + up * (style.textLift + height / 2), angle: angle)
        } else {
            let tangentDirection = tangent(middle)
            let extent = horizontalExtent(w, along: tangentDirection)
            let half = (extent / 2 + style.textGap) / Swift.max(radius, 1e-9)
            var cut: [(Double, Double)] = []
            for piece in pieces {
                if piece.1 <= middle - half || piece.0 >= middle + half { cut.append(piece); continue }
                if piece.0 < middle - half { cut.append((piece.0, middle - half)) }
                if piece.1 > middle + half { cut.append((middle + half, piece.1)) }
            }
            emit(cut, vertex: vertex, radius: radius)
            self.label(label, center: point, angle: 0)
        }
    }

    /// The four rays about the vertex, sorted; the sector is the one holding `direction`.
    private static func sector(
        _ u1: Vector2, _ u2: Vector2, containing direction: Double
    ) -> (low: (Double, Vector2), high: (Double, Vector2), sweep: Double) {
        let rays = [u1, u1 * -1, u2, u2 * -1].map { (turn(atan2($0.y, $0.x)), $0) }.sorted { $0.0 < $1.0 }
        let at = turn(direction)
        var result = (low: rays[3], high: rays[0], sweep: rays[0].0 + 2 * .pi - rays[3].0)
        for index in 0..<3 where at >= rays[index].0 && at < rays[index + 1].0 {
            result = (rays[index], rays[index + 1], rays[index + 1].0 - rays[index].0)
        }
        return result
    }

    /// Extension lines from a line's nearer end to past the arc, where the arc lies beyond the line.
    private mutating func extensionLines(vertex: Vector2, radius: Double, rays: [(Vector2, [Vector2])]) {
        for (ray, points) in rays {
            let along = points[1] - points[0]
            guard abs(ray.x * along.y - ray.y * along.x) < 1e-9 * Swift.max(1, along.length) else { continue }
            let reach = Swift.max(0, (points.map { Self.dot($0 - vertex, ray) }).max() ?? 0)
            guard radius > reach else { continue }
            let from = reach + (reach > 0 ? style.extensionGap : 0)
            line(vertex + ray * from, vertex + ray * (radius + style.extensionOvershoot))
        }
    }

    private mutating func emit(_ pieces: [(Double, Double)], vertex: Vector2, radius: Double) {
        for piece in pieces where piece.1 - piece.0 > 1e-12 {
            drawing.segments.append(.arc(center: vertex, radius: radius, start: piece.0, sweep: piece.1 - piece.0))
        }
    }
}
