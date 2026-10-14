/// The scalar maths of the field nodes (fields spec §3.2), shared by `FieldSampler` (CreatorNodes) and the implicit evaluator
/// (CreatorImplicit) so both give the same number.
public enum FieldMath {
    /// Remap's maths: the linear map of the from range onto the to range, held to the to range when `clamped`. An empty from range
    /// gives `toLow`.
    public static func remap(_ value: Double, fromLow: Double, fromHigh: Double, toLow: Double, toHigh: Double,
                             clamped: Bool) -> Double {
        guard fromHigh != fromLow else { return toLow }
        let mapped = toLow + (value - fromLow) / (fromHigh - fromLow) * (toHigh - toLow)
        guard clamped else { return mapped }
        return minimum(maximum(mapped, min(toLow, toHigh)), max(toLow, toHigh))
    }

    /// The smaller of two numbers, `.nan` when either is: Swift's `min` returns the other operand for a NaN on one side only.
    public static func minimum(_ a: Double, _ b: Double) -> Double {
        a.isNaN || b.isNaN ? .nan : min(a, b)
    }

    /// The larger of two numbers, `.nan` when either is.
    public static func maximum(_ a: Double, _ b: Double) -> Double {
        a.isNaN || b.isNaN ? .nan : max(a, b)
    }

    /// Clamp's maths: `value` held between `low` and `high`, NaN staying NaN.
    public static func clamp(_ value: Double, low: Double, high: Double) -> Double {
        minimum(maximum(value, low), high)
    }

    /// Smooth Blend's maths: the polynomial smooth minimum over `width`; width 0 is the plain minimum.
    public static func smoothMinimum(_ a: Double, _ b: Double, width: Double) -> Double {
        guard width > 0 else { return minimum(a, b) }
        guard !a.isNaN, !b.isNaN else { return .nan }
        let blend = max(width - abs(a - b), 0) / width
        return min(a, b) - blend * blend * width / 4
    }
}
