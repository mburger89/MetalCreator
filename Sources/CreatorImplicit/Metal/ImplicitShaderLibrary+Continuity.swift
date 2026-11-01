import CreatorGeometry

/// The smooth minimums of G2 and G3 (`BlendContinuity`), added to a shader only when its tree uses them.
extension ImplicitShaderLibrary {
    /// The smooth minimums of G2 and G3 (`BlendContinuity`), `min(a, b) - dip`, as `smoothMin` is for G1 (whose text stays as it was, so
    /// every G1 source is unchanged). Appended to a shader only when its tree uses them.
    static func smoothMinimum(_ continuity: BlendContinuity) -> String {
        switch continuity {
        case .g1:
            return ""
        case .g2:
            return """
                inline float smoothMin2(float a, float b, float k) {
                    if (!(k > 0.0)) { return min(a, b); }
                    float blend = max(k - abs(a - b), 0.0) / k;
                    return min(a, b) - blend * blend * blend * k / 6.0;
                }
                """
        case .g3:
            return """
                inline float smoothMin3(float a, float b, float k) {
                    if (!(k > 0.0)) { return min(a, b); }
                    float blend = max(k - abs(a - b), 0.0) / k;
                    float h2 = blend * blend;
                    return min(a, b) - h2 * h2 * (h2 - 6.0 * blend + 10.0) * k / 32.0;
                }
                """
        }
    }

    /// The text to add after the library for a tree that uses these smooth minimums and these strut lattices' joints: empty for G1 alone.
    static func extras(smoothMinimums: Set<BlendContinuity>, struts: Set<BlendContinuity>) -> String {
        ContinuityLibrary.extras(smoothMinimums: smoothMinimums, struts: struts, smoothMinimum: smoothMinimum, strutBody: lattices)
    }
}
