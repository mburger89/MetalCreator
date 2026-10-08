import CreatorGeometry
import Foundation

/// Which of the angles two lines make an angle dimension measures (spec §3, §4 branch
/// stability). Two undirected lines meet at θ and at 180° − θ, on either side, so a bare value is
/// ambiguous; the sense picks one of the four once, when the dimension is created (or on its
/// first solve), and the solver then meets the value only that way. Typing 120 on a 60° vee
/// opens it to 120°, and a sweep through 90° never folds back.
///
/// The measured angle runs from the first line's direction (start → end) to the second line's
/// direction, reversed when `reversesSecond`, counter-clockwise unless `isClockwise`.
public struct AngleSense: Hashable, Sendable, Codable {
    public var isClockwise: Bool
    public var reversesSecond: Bool

    public init(isClockwise: Bool, reversesSecond: Bool) {
        self.isClockwise = isClockwise
        self.reversesSecond = reversesSecond
    }

    /// The signed angle (radians) from `first` to `second`, the directions as drawn, that a value of
    /// `degrees` in this sense asks for.
    func directedTarget(degrees: Double) -> Double {
        let theta = degrees * .pi / 180
        let signed = isClockwise ? -theta : theta
        return reversesSecond ? signed - .pi : signed
    }

    /// The value (degrees) this sense reads from two directions, in (−180°, 180°]: negative when
    /// the geometry has swung past 0° the other way.
    func degrees(from first: Vector2, to second: Vector2) -> Double {
        let phi = Self.signedAngle(from: first, to: second)
        let measured = reversesSecond ? phi + .pi : phi
        let signed = isClockwise ? -measured : measured
        return Self.wrappedToHalfTurn(signed) * 180 / .pi
    }

    /// The sense whose target for `degrees` is nearest the angle the directions make now. Ties go
    /// to the second line as drawn, then to counter-clockwise.
    static func nearest(from first: Vector2, to second: Vector2, degrees: Double) -> AngleSense {
        let phi = signedAngle(from: first, to: second)
        let candidates = [false, true].flatMap { reverses in
            [false, true].map { clockwise in AngleSense(isClockwise: clockwise, reversesSecond: reverses) }
        }
        var best = candidates[0]
        var bestGap = Double.infinity
        for candidate in candidates {
            let gap = abs(wrappedToHalfTurn(phi - candidate.directedTarget(degrees: degrees)))
            if gap < bestGap - 1e-12 {
                best = candidate
                bestGap = gap
            }
        }
        return best
    }

    /// The signed angle from `a` to `b`, in (−π, π].
    static func signedAngle(from a: Vector2, to b: Vector2) -> Double {
        atan2(SketchMath.cross(a, b), SketchMath.dot(a, b))
    }

    /// `angle` wrapped into (−π, π].
    static func wrappedToHalfTurn(_ angle: Double) -> Double {
        let wrapped = SketchMath.wrapped(angle)
        return wrapped > .pi ? wrapped - 2 * .pi : wrapped
    }
}
