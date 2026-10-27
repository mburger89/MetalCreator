import CreatorGeometry
import CreatorGraph

/// The slack of every wire in motion (cable ties spec 2026-10-26 §5.2): a `PieceSpring` for each piece of each wire whose
/// pinned points moved, as of `time` (seconds, the editor's motion clock). At rest it holds nothing. A drawn route keeps its
/// pinned points exactly and only its control points carry the slack. Pure: the canvas reads `advanced(to:)` at each frame's
/// date and never writes it back.
public struct WireMotion: Equatable, Sendable {
    public private(set) var springs: [Endpoint: [PieceSpring]] = [:]
    public private(set) var time = 0.0

    public init() {}

    public var isAtRest: Bool { springs.isEmpty }

    /// This motion at `time`; unchanged for a time not after its own, so a frame dated before the last kick changes nothing.
    public func advanced(to time: Double) -> WireMotion {
        guard time > self.time else { return self }
        var next = self
        next.time = time
        next.springs = springs.compactMapValues { pieces in
            let stepped = pieces.map { WireSpring.evolve($0, dt: time - self.time) }
            return stepped.allSatisfy(\.isAtRest) ? nil : stepped
        }
        return next
    }

    /// Advances to `time`, then kicks each wire's pieces by how its pinned points moved from `before` to `after` (display
    /// canvas points, by wire). A wire whose route changed shape (a tie added or removed) or appeared starts taut; one that
    /// is gone is dropped.
    public mutating func excite(from before: [Endpoint: [Vector2]], to after: [Endpoint: [Vector2]], at time: Double) {
        self = advanced(to: time)
        var kicked: [Endpoint: [PieceSpring]] = [:]
        for (wire, points) in after {
            guard let old = before[wire], old.count == points.count, points.count >= 2 else { continue }
            let current = springs[wire].flatMap { $0.count == points.count - 1 ? $0 : nil }
                ?? Array(repeating: PieceSpring(), count: points.count - 1)
            let pieces = current.indices.map { index in
                WireSpring.kick(current[index], startDelta: points[index] - old[index],
                                endDelta: points[index + 1] - old[index + 1],
                                length: (points[index + 1] - points[index]).length)
            }
            if !pieces.allSatisfy(\.isAtRest) { kicked[wire] = pieces }
        }
        springs = kicked
    }

    /// `route` as drawn now: its pinned points exactly where they are, its control points moved by their springs. A route
    /// with no spring, or a different number of pieces than its spring, is drawn taut.
    public func drawn(_ route: WireRoute) -> WireRoute {
        guard let pieces = springs[route.wire], pieces.count == route.pieces.count else { return route }
        return WireRoute(wire: route.wire, pieces: zip(route.pieces, pieces).map { piece, spring in
            WireGeometry(start: piece.start, control1: piece.control1 + spring.control1.offset,
                         control2: piece.control2 + spring.control2.offset, end: piece.end)
        })
    }
}
