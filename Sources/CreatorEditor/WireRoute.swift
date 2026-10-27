import CreatorGeometry
import CreatorGraph

/// A wire's taut route (cable ties spec 2026-10-26 §5.1) in display canvas points: one cubic from its output to its input, or
/// a chain of them through the lane of each tie that holds it. Each piece leaves and enters along the flow with
/// `WireGeometry`'s reach rule, so the pieces join tangent-continuously at every lane and an untied wire is exactly the cubic
/// it always was. Hit testing, box selection, culling and the place of a new tie read this route, never the slack one
/// (§5.2).
public struct WireRoute: Equatable, Sendable {
    /// How many segments each piece is sampled into for hit testing and boxes.
    public static let samplesPerPiece = 24

    /// The wire, named by its input endpoint.
    public var wire: Endpoint
    /// The pieces, the output end first.
    public var pieces: [WireGeometry]

    public init(wire: Endpoint, pieces: [WireGeometry]) {
        self.wire = wire
        self.pieces = pieces
    }

    /// The route through `points`: the output's anchor, each lane in order, the input's anchor.
    public init(wire: Endpoint, through points: [Vector2], flow: CanvasFlow) {
        self.init(wire: wire, pieces: zip(points, points.dropFirst()).map { WireGeometry(from: $0, to: $1, flow: flow) })
    }

    /// The points the route passes through exactly (§5.2's pinned points): its two ends and each lane.
    public var pinned: [Vector2] { (pieces.first.map { [$0.start] } ?? []) + pieces.map(\.end) }

    /// The route as a polyline, `samplesPerPiece` segments a piece, from the output end.
    public var samples: [Vector2] {
        var points = pieces.first.map { [$0.start] } ?? []
        for piece in pieces {
            for step in 1...Self.samplesPerPiece {
                points.append(piece.point(at: Double(step) / Double(Self.samplesPerPiece)))
            }
        }
        return points
    }

    /// The middle sample: where a wire with no pick point puts a new tie (cable ties plan ruling R10).
    public var middle: Vector2 {
        let points = samples
        return points.isEmpty ? .zero : points[points.count / 2]
    }

    /// A rectangle holding every piece, grown by `padding`.
    public func bounds(padding: Double) -> CanvasRect { WireGeometry.bounds(of: pieces, padding: padding) }

    /// How far `point` is from the route's polyline.
    public func distance(to point: Vector2) -> Double {
        let points = samples
        return zip(points, points.dropFirst()).map { Self.distance(from: point, toSegment: $0, $1) }.min() ?? .infinity
    }

    /// The middle of each stretch of the route inside `rect`; empty when it never enters it.
    public func pointsInside(_ rect: CanvasRect) -> [Vector2] {
        let points = samples
        return zip(points, points.dropFirst()).compactMap { Self.clip($0, $1, to: rect) }.map { ($0.0 + $0.1) * 0.5 }
    }

    /// Whether the route crosses or lies inside `rect`.
    public func intersects(_ rect: CanvasRect) -> Bool { !pointsInside(rect).isEmpty }

    static func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return (p - a).length }
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared, 0), 1)
        return (a + ab * t - p).length
    }

    /// The part of segment `a`–`b` inside `rect` (Liang–Barsky), or `nil` when it misses.
    static func clip(_ a: Vector2, _ b: Vector2, to rect: CanvasRect) -> (Vector2, Vector2)? {
        let d = b - a
        var low = 0.0, high = 1.0
        let edges = [(-d.x, a.x - rect.origin.x), (d.x, rect.maxX - a.x), (-d.y, a.y - rect.origin.y), (d.y, rect.maxY - a.y)]
        for (p, q) in edges {
            if p == 0 {
                if q < 0 { return nil }
                continue
            }
            let r = q / p
            if p < 0 { low = max(low, r) } else { high = min(high, r) }
            if low > high { return nil }
        }
        return (a + d * low, a + d * high)
    }
}
