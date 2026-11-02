import CreatorGeometry

/// The HLSL twin of `ImplicitShaderLibrary+Continuity`: G2 and G3 smooth minimums, every float `precise`.
extension HLSLShaderLibrary {
    /// `ImplicitShaderLibrary.smoothMinimum`, ported: G2 and G3's smooth minimums, every float `precise`.
    static func smoothMinimum(_ continuity: BlendContinuity) -> String {
        switch continuity {
        case .g1:
            return ""
        case .g2:
            return """
                precise float smoothMin2(float a, float b, float k) {
                    if (!(k > 0.0f)) { return min(a, b); }
                    precise float blend = max(k - abs(a - b), 0.0f) / k;
                    return min(a, b) - blend * blend * blend * k / 6.0f;
                }
                """
        case .g3:
            return """
                precise float smoothMin3(float a, float b, float k) {
                    if (!(k > 0.0f)) { return min(a, b); }
                    precise float blend = max(k - abs(a - b), 0.0f) / k;
                    precise float h2 = blend * blend;
                    return min(a, b) - h2 * h2 * (h2 - 6.0f * blend + 10.0f) * k / 32.0f;
                }
                """
        }
    }

    /// What follows the library for a tree that uses these continuities (see `ContinuityLibrary`).
    static func extras(smoothMinimums: Set<BlendContinuity>, struts: Set<BlendContinuity>) -> String {
        ContinuityLibrary.extras(smoothMinimums: smoothMinimums, struts: struts, smoothMinimum: smoothMinimum, strutBody: lattices)
    }
}
