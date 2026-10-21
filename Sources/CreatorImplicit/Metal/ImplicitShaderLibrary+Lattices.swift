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

    // The lattice bodies read the lattice coordinates `m` of a point (the point itself when the mapping is Straight); the compiled sdf
    // joins the body with the mapping's singular set and cuts it to the region at the point.
    inline float tpmsBody(float3 m, float cell, float3 stretch, float thickness, int type, int form, float wallScale) {
        const float twoPi = 6.28318530717958647692;
        float size = max(cell, 0.000001);
        float3 u = m / (size * stretch);
        float3 q = twoPi * (u - floor(u));
        float core = tpmsRaw(type, q) * size / (twoPi * wallScale);
        float wall = max(thickness, 0.0);
        return form == 0 ? abs(core) - wall * 0.5 : core - wall * 0.5;
    }

    // MARK: strut lattices (StrutLattice)

    inline float segmentDistance(float3 p, float3 a, float3 b) {
        float3 along = b - a;
        float length2 = dot(along, along);
        float t = length2 > 0.0 ? clamp(dot(p - a, along) / length2, 0.0, 1.0) : 0.0;
        return length(p - a - along * t);
    }

    inline float strutBody(const thread Env& e, int offset, int count, float3 m, float cell, float3 stretch, float radius, float blend) {
        float size = max(cell, 0.000001);
        float3 edges = size * stretch;
        float3 index = floor(m / edges);
        float nearest = 1e30;
        for (int dz = -1; dz <= 1; dz++) {
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    float3 base = index + float3(float(dx), float(dy), float(dz));
                    for (int s = 0; s < count; s++) {
                        int at = offset + 6 * s;
                        float3 start = (base + float3(e.pool[at], e.pool[at + 1], e.pool[at + 2])) * edges;
                        float3 end = (base + float3(e.pool[at + 3], e.pool[at + 4], e.pool[at + 5])) * edges;
                        nearest = smoothMin(nearest, segmentDistance(m, start, end), blend);
                    }
                }
            }
        }
        float reach = 0.85 * min(edges.x, min(edges.y, edges.z));
        return min(nearest, reach) - max(radius, 0.0);
    }

    // MARK: Voronoi lattices (VoronoiLattice)

    inline float3 seedAt(const thread Env& e, int pointsAt, int seed) {
        return float3(e.pool[pointsAt + 3 * seed], e.pool[pointsAt + 3 * seed + 1], e.pool[pointsAt + 3 * seed + 2]);
    }

    inline float voronoiBody(const thread Env& e, int ioff, int poff, float3 m, float thickness, int form, float strutScale) {
        int pointsAt = e.I[ioff], startsAt = e.I[ioff + 1], entriesAt = e.I[ioff + 2];
        int3 counts = int3(e.I[ioff + 3], e.I[ioff + 4], e.I[ioff + 5]);
        float3 origin = float3(e.P[poff], e.P[poff + 1], e.P[poff + 2]);
        float radius = e.P[poff + 3];
        float3 cellAt = clamp(floor((m - origin) / radius), float3(-2.0), float3(counts) + 1.0);
        int3 cell = int3(cellAt);
        float d1 = INFINITY, d2 = INFINITY, d3 = INFINITY;
        int nearest = -1;
        for (int dz = -1; dz <= 1; dz++) {
            int z = cell.z + dz;
            if (z < 0 || z >= counts.z) { continue; }
            for (int dy = -1; dy <= 1; dy++) {
                int y = cell.y + dy;
                if (y < 0 || y >= counts.y) { continue; }
                for (int dx = -1; dx <= 1; dx++) {
                    int x = cell.x + dx;
                    if (x < 0 || x >= counts.x) { continue; }
                    int index = (z * counts.y + y) * counts.x + x;
                    for (int k = e.tables[startsAt + index]; k < e.tables[startsAt + index + 1]; k++) {
                        int seed = e.tables[entriesAt + k];
                        float d = length(m - seedAt(e, pointsAt, seed));
                        if (d < d1) { d3 = d2; d2 = d1; d1 = d; nearest = seed; }
                        else if (d < d2) { d3 = d2; d2 = d; }
                        else if (d < d3) { d3 = d; }
                    }
                }
            }
        }
        float wall = max(thickness, 0.0);
        float body;
        if (form == 0) {
            body = (min(d3, radius) - min(d1, radius)) / strutScale - wall * 0.5;
        } else {
            float distance = max(0.0, (radius - d1) * 0.5);
            if (nearest >= 0) {
                float3 first = seedAt(e, pointsAt, nearest);
                for (int dz = -1; dz <= 1; dz++) {
                    int z = cell.z + dz;
                    if (z < 0 || z >= counts.z) { continue; }
                    for (int dy = -1; dy <= 1; dy++) {
                        int y = cell.y + dy;
                        if (y < 0 || y >= counts.y) { continue; }
                        for (int dx = -1; dx <= 1; dx++) {
                            int x = cell.x + dx;
                            if (x < 0 || x >= counts.x) { continue; }
                            int index = (z * counts.y + y) * counts.x + x;
                            for (int k = e.tables[startsAt + index]; k < e.tables[startsAt + index + 1]; k++) {
                                int seed = e.tables[entriesAt + k];
                                float3 position = seedAt(e, pointsAt, seed);
                                float3 across = position - first;
                                float length2 = length(across);
                                if (seed == nearest || length2 <= 0.000000001) { continue; }
                                distance = min(distance, dot(across, (first + position) * 0.5 - m) / length2);
                            }
                        }
                    }
                }
            }
            body = distance - wall * 0.5;
        }
        return body;
    }

    // MARK: lattice mappings (LatticeMapping)

    inline float3 mapCylindrical(float3 p, float3 origin, float3 reference, float3 side, float3 axis, float radius) {
        float3 offset = p - origin;
        float x = dot(offset, reference), y = dot(offset, side);
        return float3(precise::atan2(y, x) * radius, dot(offset, axis), sqrt(x * x + y * y));
    }

    inline float singularCylindrical(float3 p, float3 origin, float3 reference, float3 side) {
        float3 offset = p - origin;
        float x = dot(offset, reference), y = dot(offset, side);
        return sqrt(x * x + y * y);
    }

    inline float3 mapSpherical(float3 p, float3 centre, float radius) {
        float3 offset = p - centre;
        float across = sqrt(offset.x * offset.x + offset.y * offset.y);
        return float3(precise::atan2(offset.y, offset.x) * radius, precise::atan2(offset.z, across) * radius, length(offset));
    }

    inline float singularSpherical(float3 p, float3 centre) {
        float3 offset = p - centre;
        return sqrt(offset.x * offset.x + offset.y * offset.y);
    }

    // FaceMap.coordinates: `h` is where the chart's header is in the integers (its flags, then the slots of the first coordinate's cosine
    // and sine, the second's and the depth); a periodic coordinate is the angle of its cosine and sine times the length of a radian.
    inline float3 mapFace(const thread Env& e, int h, float3 p, float firstRadius, float secondRadius) {
        int flags = e.I[h];
        float a = bakedChannel(e, e.I[h + 1], e.I[h + 2], p);
        if ((flags & 1) != 0) { a = precise::atan2(bakedChannel(e, e.I[h + 3], e.I[h + 4], p), a) * firstRadius; }
        float b = bakedChannel(e, e.I[h + 5], e.I[h + 6], p);
        if ((flags & 2) != 0) { b = precise::atan2(bakedChannel(e, e.I[h + 7], e.I[h + 8], p), b) * secondRadius; }
        return float3(a, b, bakedChannel(e, e.I[h + 9], e.I[h + 10], p));
    }

    // LatticeMapping.join: the body beyond the exclusion and its fade, solid within the exclusion, a blend between.
    inline float mappingJoin(float body, float singular, float exclusion, float fade) {
        float weight = clamp((singular - exclusion) / fade, 0.0, 1.0);
        float solid = singular - exclusion;
        if (weight >= 1.0) { return body; }
        return weight <= 0.0 ? solid : weight * body + (1.0 - weight) * solid;
    }
    """
}
