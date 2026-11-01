/// How smoothly a smooth minimum joins its two operands (G-a of the G2 surfacing spec). With `h = max(k − |a − b|, 0) / k` the
/// smooth minimum is `min(a, b) − dip`, where the dip is `h²·k/4` (G1), `h³·k/6` (G2) or `h³(4 − h)·k/16` (G3): each is zero
/// at the edge of the blend, where the value and the derivatives up to the continuity's order agree with the plain minimum.
public enum BlendContinuity: Int, Hashable, Sendable, Codable, CaseIterable {
    case g1 = 0
    case g2 = 1
    case g3 = 2

    /// The dip below the plain minimum for a blend of width `width` and a gap `|a − b|` of `gap`.
    public func dip(width: Double, gap: Double) -> Double {
        let h = max(width - gap, 0) / width
        switch self {
        case .g1: return h * h * width / 4
        case .g2: return h * h * h * width / 6
        case .g3: return h * h * h * (4 - h) * width / 16
        }
    }

    /// A bound on how fast the dip changes with the width at a fixed gap: the maximum over `h` of `∂dip/∂k`, which is reached at
    /// `h = 1` (where `a = b`). With `h = 1 − gap/k`, `∂dip/∂k = f(h) + (1 − h)·f'(h)` for the dip `k·f(h)`: G1 gives
    /// `h/2 − h²/4` (1/4 at `h = 1`), G2 `h²/2 − h³/3` (1/6) and G3 `3h²(2 − h)²/16` (3/16), each rising on `[0, 1]`.
    public var dipSlope: Double {
        switch self {
        case .g1: 0.25
        case .g2: 1.0 / 6.0
        case .g3: 3.0 / 16.0
        }
    }

    /// "G1", "G2" or "G3".
    public var label: String {
        switch self {
        case .g1: "G1"
        case .g2: "G2"
        case .g3: "G3"
        }
    }
}
