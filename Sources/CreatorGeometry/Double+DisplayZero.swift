import Foundation

extension Double {
    /// This value rounded to `decimals` places, with every zero (a tiny negative, -0.0) made the positive zero. Format the result:
    /// a negative zero is decided here from the number, never from the formatted text, whose minus sign and digits depend on the
    /// locale (sv_SE writes U+2212, fa_IR and ar_EG write other digits and marks).
    public func roundedForDisplay(decimals: Int) -> Double {
        let scale = pow(10, Double(decimals))
        let scaled = (self * scale).rounded(.toNearestOrAwayFromZero)
        guard scaled.isFinite else { return self } // too large to scale, so it has no decimals to round
        let rounded = scaled / scale
        return rounded == 0 ? 0 : rounded
    }
}
