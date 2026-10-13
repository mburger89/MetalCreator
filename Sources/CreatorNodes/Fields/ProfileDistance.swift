import CreatorGeometry
import Foundation

/// The distance from a point to a profile's loops (fields spec §3.1): to its edges, not its area, measured in 3D, so a
/// point above the plane adds its height. Plain Swift; it never reaches the kernel.
struct ProfileDistance: Sendable {
    private enum Piece: Sendable {
        case line(Vector2, Vector2)
        /// An arc is the part of its circle from `lowest` through `sweep` radians, counter-clockwise (a clockwise arc is the
        /// same points run backwards).
        case arc(center: Vector2, radius: Double, lowest: Double, sweep: Double)
    }

    private let plane: Plane
    private let pieces: [Piece]

    init(_ profile: Profile2D) {
        plane = profile.plane
        pieces = profile.loops.joined().map { segment in
            switch segment {
            case .line(let a, let b):
                .line(a, b)
            case .arc(let center, let radius, let start, let end):
                .arc(center: center, radius: radius, lowest: min(start.radians, end.radians), sweep: abs(end.radians - start.radians))
            }
        }
    }

    /// Millimetres from `point` to the nearest of the loops' pieces.
    func distance(from point: Vector3) -> Double {
        let offset = point - plane.origin
        let local = Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
        let height = offset.dot(plane.normal)
        let inPlane = pieces.map { Self.distance(from: local, to: $0) }.min() ?? .infinity
        return (inPlane * inPlane + height * height).squareRoot()
    }

    private static func distance(from point: Vector2, to piece: Piece) -> Double {
        switch piece {
        case .line(let a, let b):
            let direction = b - a
            let lengthSquared = direction.x * direction.x + direction.y * direction.y
            guard lengthSquared > 0 else { return (point - a).length }
            let along = min(1, max(0, ((point.x - a.x) * direction.x + (point.y - a.y) * direction.y) / lengthSquared))
            return (point - (a + direction * along)).length
        case .arc(let center, let radius, let lowest, let sweep):
            let offset = point - center
            let away = offset.length
            guard away > 0 else { return radius }
            var angle = (atan2(offset.y, offset.x) - lowest).truncatingRemainder(dividingBy: 2 * .pi)
            if angle < 0 { angle += 2 * .pi }
            if sweep >= 2 * .pi - 1e-9 || angle <= sweep { return abs(away - radius) }
            let start = center + Vector2(cos(lowest), sin(lowest)) * radius
            let end = center + Vector2(cos(lowest + sweep), sin(lowest + sweep)) * radius
            return min((point - start).length, (point - end).length)
        }
    }
}
