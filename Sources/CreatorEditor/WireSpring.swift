import CreatorGeometry
import Foundation

/// The spring that gives a moving wire its slack (cable ties spec 2026-10-26 §5.2), as pure functions of one piece's state.
/// `kick` handles the piece's pinned ends moving: the control points lag their taut places by `slack` of the move. `evolve`
/// lets the damped spring pull them back. It is solved in closed form, so it is exact for any `dt` and a long frame cannot
/// overshoot. The offset is capped at `capFraction` of the piece's length so the piece never folds over. A state too small
/// to see snaps to exactly zero, and the drawn piece is then the taut piece bit for bit. The constants are tuned by eye
/// (human check TIE-1).
public enum WireSpring {
    /// Radians a second. With the damping below, the slack is under 2.5% of itself after 0.3 s.
    public static let naturalFrequency = 20.0
    public static let dampingRatio = 0.8
    public static let slack = 0.6
    public static let capFraction = 0.4
    /// Below these (points, points a second), on both control points, the piece is at rest.
    public static let restOffset = 0.05
    public static let restSpeed = 1.0

    /// The pure step of spec §5.2: `state` kicked by its ends' moves, then `dt` seconds of spring.
    public static func step(_ state: PieceSpring, startDelta: Vector2, endDelta: Vector2, length: Double,
                            dt: Double) -> PieceSpring {
        evolve(kick(state, startDelta: startDelta, endDelta: endDelta, length: length), dt: dt)
    }

    /// `state` after its start moved by `startDelta` and its end by `endDelta`, the piece now `length` long.
    public static func kick(_ state: PieceSpring, startDelta: Vector2, endDelta: Vector2, length: Double) -> PieceSpring {
        var next = state
        next.cap = capFraction * max(length, 0)
        next.control1.offset = capped(state.control1.offset - startDelta * slack, to: next.cap)
        next.control2.offset = capped(state.control2.offset - endDelta * slack, to: next.cap)
        return settled(next)
    }

    /// `state` after `dt` seconds of the damped spring; unchanged for a `dt` that isn't positive.
    public static func evolve(_ state: PieceSpring, dt: Double) -> PieceSpring {
        guard !state.isAtRest, dt > 0 else { return state }
        var next = state
        next.control1 = evolve(state.control1, dt: dt, cap: state.cap)
        next.control2 = evolve(state.control2, dt: dt, cap: state.cap)
        return settled(next)
    }

    static func evolve(_ point: SpringPoint, dt: Double, cap: Double) -> SpringPoint {
        let (x, vx) = oscillate(point.offset.x, point.velocity.x, dt: dt)
        let (y, vy) = oscillate(point.offset.y, point.velocity.y, dt: dt)
        return SpringPoint(offset: capped(Vector2(x, y), to: cap), velocity: Vector2(vx, vy))
    }

    /// One axis of the under-damped spring after `dt`, exactly: offset `x` and velocity `v` in, the same out.
    static func oscillate(_ x: Double, _ v: Double, dt: Double) -> (Double, Double) {
        let sigma = dampingRatio * naturalFrequency
        let omega = naturalFrequency * (1 - dampingRatio * dampingRatio).squareRoot()
        let decay = exp(-sigma * dt), c = cos(omega * dt), s = sin(omega * dt)
        let a = (v + sigma * x) / omega
        let position = x * c + a * s
        return (decay * position, decay * (omega * (a * c - x * s) - sigma * position))
    }

    static func capped(_ offset: Vector2, to cap: Double) -> Vector2 {
        let length = offset.length
        return length > cap && length > 0 ? offset * (cap / length) : offset
    }

    /// `state`, or exactly zero once both control points are too close and too slow to see.
    static func settled(_ state: PieceSpring) -> PieceSpring {
        let quiet = [state.control1, state.control2].allSatisfy { $0.offset.length < restOffset && $0.velocity.length < restSpeed }
        return quiet ? PieceSpring() : state
    }
}
