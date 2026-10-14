/// The Metal Shading Language of the lattices (implicit spec §3.4), after the shared library. Each function is a line-for-line port of
/// its twin in `CPUEvaluation+Lattices`; the agreement suite holds the two to 1e-4 mm. Trigonometry is `precise::` and its argument
/// is reduced to one period first, because the default fast sine is not accurate at the large arguments a small cell gives.
extension ImplicitShaderLibrary {
    static let lattices = """
    // MARK: TPMS lattices (TPMSLattice)

    inline float tpmsRaw(int type, float3 q) {
        float3 s = precise::sin(q), c = precise::cos(q);
        if (type == 0) { return s.x * c.y + s.y * c.z + s.z * c.x; }
        if (type == 1) { return c.x + c.y + c.z; }
        if (type == 2) { return s.x * s.y * s.z + s.x * c.y * c.z + c.x * s.y * c.z + c.x * c.y * s.z; }
        if (type == 3) { return 3.0 * (c.x + c.y + c.z) + 4.0 * c.x * c.y * c.z; }
        float first = precise::sin(2.0 * q.x) * c.y * s.z + precise::sin(2.0 * q.y) * c.z * s.x + precise::sin(2.0 * q.z) * c.x * s.y;
        float second = precise::cos(2.0 * q.x) * precise::cos(2.0 * q.y) + precise::cos(2.0 * q.y) * precise::cos(2.0 * q.z)
            + precise::cos(2.0 * q.z) * precise::cos(2.0 * q.x);
        return 0.5 * first - 0.5 * second + 0.15;
    }

    inline float tpmsLattice(float3 p, float cell, float3 stretch, float thickness, int type, int form, float wallScale,
                             float3 centre, float3 halfSize) {
        const float twoPi = 6.28318530717958647692;
        float size = max(cell, 0.000001);
        float3 u = p / (size * stretch);
        float3 q = twoPi * (u - floor(u));
        float core = tpmsRaw(type, q) * size / (twoPi * wallScale);
        float wall = max(thickness, 0.0);
        float body = form == 0 ? abs(core) - wall * 0.5 : core - wall * 0.5;
        return max(body, regionDistance(p, centre, halfSize));
    }
    """
}
