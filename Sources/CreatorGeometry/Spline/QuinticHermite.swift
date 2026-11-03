import Foundation

/// One quintic Hermite span (sketch splines spec, "The curve"): from `p0` to `p1` over a parameter interval of length `h`, with
/// the first derivative `t` and second derivative `a` (both with respect to that parameter) at each end. Its Bézier form is
/// exact, and everything else a spline needs follows from it.
struct QuinticHermite: Sendable {
    var p0: Vector2
    var p1: Vector2
    var t0: Vector2
    var t1: Vector2
    var a0: Vector2
    var a1: Vector2
    var h: Double

    /// The six Bézier poles of the span over its local parameter 0…1 (the span's own `h` is folded in).
    var bezier: [Vector2] {
        let (ht0, ht1) = (t0 * h, t1 * h)
        let (ha0, ha1) = (a0 * (h * h / 20), a1 * (h * h / 20))
        return [p0, p0 + ht0 * 0.2, p0 + ht0 * 0.4 + ha0, p1 - ht1 * 0.4 + ha1, p1 - ht1 * 0.2, p1]
    }

    /// The linear functionals that give the third and fourth derivatives (with respect to the span's parameter) at its start and
    /// end from the Hermite data, in the order `p0, p1, t0, t1, a0, a1`. They are what the automatic handles are solved from.
    enum Derivative: CaseIterable {
        case thirdAtStart, thirdAtEnd, fourthAtStart, fourthAtEnd
    }

    static func coefficients(of derivative: Derivative, h: Double) -> [Double] {
        let h2 = h * h
        switch derivative {
        case .thirdAtStart:
            let s = 60 / (h * h2)
            return [-s, s, -s * 3 * h / 5, -s * 2 * h / 5, -s * 3 * h2 / 20, s * h2 / 20]
        case .thirdAtEnd:
            let s = 60 / (h * h2)
            return [-s, s, -s * 2 * h / 5, -s * 3 * h / 5, -s * h2 / 20, s * 3 * h2 / 20]
        case .fourthAtStart:
            let s = 120 / (h2 * h2)
            return [3 * s, -3 * s, s * 8 * h / 5, s * 7 * h / 5, s * 3 * h2 / 10, -s * h2 / 5]
        case .fourthAtEnd:
            let s = 120 / (h2 * h2)
            return [-3 * s, 3 * s, -s * 7 * h / 5, -s * 8 * h / 5, -s * h2 / 5, s * 3 * h2 / 10]
        }
    }
}
