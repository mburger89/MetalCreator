/// `ImplicitShaderLibrary.lattices`, ported (implicit spec §3.4, §3.5): TPMS, struts, Voronoi and the mappings, trigonometry through
/// `accSin`,
/// `accCos` and `accAtan2`.
extension HLSLShaderLibrary {
    static let lattices = """
    // The lattices and their mappings (implicit spec §3.4, §3.5): a port of ImplicitShaderLibrary.lattices, trigonometry through
    // accurate_math.hlsli.

    float tpmsRaw(int type, float3 q) {
        float3 s = accSin3(q), c = accCos3(q);
        if (type == 0) { return s.x * c.y + s.y * c.z + s.z * c.x; }
        if (type == 1) { return c.x + c.y + c.z; }
        if (type == 2) { return s.x * s.y * s.z + s.x * c.y * c.z + c.x * s.y * c.z + c.x * c.y * s.z; }
        if (type == 3) { return 3.0f * (c.x + c.y + c.z) + 4.0f * c.x * c.y * c.z; }
        float first = accSin(2.0f * q.x) * c.y * s.z + accSin(2.0f * q.y) * c.z * s.x + accSin(2.0f * q.z) * c.x * s.y;
        float second = accCos(2.0f * q.x) * accCos(2.0f * q.y) + accCos(2.0f * q.y) * accCos(2.0f * q.z)
            + accCos(2.0f * q.z) * accCos(2.0f * q.x);
        return 0.5f * first - 0.5f * second + 0.15f;
    }

    float tpmsBody(float3 m, float cell, float3 stretch, float thickness, int type, int form, float wallScale) {
        const float twoPi = 6.28318530717958647692f;
        float size = max(cell, 0.000001f);
        float3 u = m / (size * stretch);
        float3 q = twoPi * (u - floor(u));
        float core = tpmsRaw(type, q) * size / (twoPi * wallScale);
        float wall = max(thickness, 0.0f);
        return form == 0 ? abs(core) - wall * 0.5f : core - wall * 0.5f;
    }

    float segmentDistance(float3 p, float3 a, float3 b) {
        float3 along = b - a;
        float length2 = dot(along, along);
        float t = length2 > 0.0f ? clamp(dot(p - a, along) / length2, 0.0f, 1.0f) : 0.0f;
        return length(p - a - along * t);
    }

    float strutBody(int offset, int count, float3 m, float cell, float3 stretch, float radius, float blend) {
        float size = max(cell, 0.000001f);
        float3 edges = size * stretch;
        float3 index = floor(m / edges);
        float nearest = 1e30f;
        for (int dz = -1; dz <= 1; dz++) {
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    float3 base = index + float3(float(dx), float(dy), float(dz));
                    for (int s = 0; s < count; s++) {
                        int at = offset + 6 * s;
                        float3 start = (base + float3(POOL(at), POOL(at + 1), POOL(at + 2))) * edges;
                        float3 end = (base + float3(POOL(at + 3), POOL(at + 4), POOL(at + 5))) * edges;
                        nearest = smoothMin(nearest, segmentDistance(m, start, end), blend);
                    }
                }
            }
        }
        float reach = 0.85f * min(edges.x, min(edges.y, edges.z));
        return min(nearest, reach) - max(radius, 0.0f);
    }

    float3 seedAt(int pointsAt, int seed) {
        return float3(POOL(pointsAt + 3 * seed), POOL(pointsAt + 3 * seed + 1), POOL(pointsAt + 3 * seed + 2));
    }

    float voronoiBody(int ioff, int poff, float3 m, float thickness, int form, float strutScale) {
        int pointsAt = I(ioff), startsAt = I(ioff + 1), entriesAt = I(ioff + 2);
        int3 counts = int3(I(ioff + 3), I(ioff + 4), I(ioff + 5));
        float3 origin = PV(poff);
        float radius = P(poff + 3);
        float3 cellAt = clamp(floor((m - origin) / radius), float3(-2.0f, -2.0f, -2.0f), float3(counts) + 1.0f);
        int3 cell = int3(cellAt);
        float d1 = INFINITY_F, d2 = INFINITY_F, d3 = INFINITY_F;
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
                    for (int k = TABLES(startsAt + index); k < TABLES(startsAt + index + 1); k++) {
                        int seed = TABLES(entriesAt + k);
                        float d = length(m - seedAt(pointsAt, seed));
                        if (d < d1) { d3 = d2; d2 = d1; d1 = d; nearest = seed; }
                        else if (d < d2) { d3 = d2; d2 = d; }
                        else if (d < d3) { d3 = d; }
                    }
                }
            }
        }
        float wall = max(thickness, 0.0f);
        float body;
        if (form == 0) {
            body = (min(d3, radius) - min(d1, radius)) / strutScale - wall * 0.5f;
        } else {
            float distance = max(0.0f, (radius - d1) * 0.5f);
            if (nearest >= 0) {
                float3 first = seedAt(pointsAt, nearest);
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
                            for (int k = TABLES(startsAt + index); k < TABLES(startsAt + index + 1); k++) {
                                int seed = TABLES(entriesAt + k);
                                float3 position = seedAt(pointsAt, seed);
                                float3 across = position - first;
                                float length2 = length(across);
                                if (seed == nearest || length2 <= 0.000000001f) { continue; }
                                distance = min(distance, dot(across, (first + position) * 0.5f - m) / length2);
                            }
                        }
                    }
                }
            }
            body = distance - wall * 0.5f;
        }
        return body;
    }

    float3 mapCylindrical(float3 p, float3 origin, float3 reference, float3 side, float3 axis, float radius) {
        float3 offset = p - origin;
        float x = dot(offset, reference), y = dot(offset, side);
        return float3(accAtan2(y, x) * radius, dot(offset, axis), sqrt(x * x + y * y));
    }

    float singularCylindrical(float3 p, float3 origin, float3 reference, float3 side) {
        float3 offset = p - origin;
        float x = dot(offset, reference), y = dot(offset, side);
        return sqrt(x * x + y * y);
    }

    float3 mapSpherical(float3 p, float3 centre, float radius) {
        float3 offset = p - centre;
        float across = sqrt(offset.x * offset.x + offset.y * offset.y);
        return float3(accAtan2(offset.y, offset.x) * radius, accAtan2(offset.z, across) * radius, length(offset));
    }

    float singularSpherical(float3 p, float3 centre) {
        float3 offset = p - centre;
        return sqrt(offset.x * offset.x + offset.y * offset.y);
    }

    float3 mapFace(int h, float3 p, float firstRadius, float secondRadius) {
        int flags = I(h);
        float a = bakedChannel(I(h + 1), I(h + 2), p);
        if ((flags & 1) != 0) { a = accAtan2(bakedChannel(I(h + 3), I(h + 4), p), a) * firstRadius; }
        float b = bakedChannel(I(h + 5), I(h + 6), p);
        if ((flags & 2) != 0) { b = accAtan2(bakedChannel(I(h + 7), I(h + 8), p), b) * secondRadius; }
        return float3(a, b, bakedChannel(I(h + 9), I(h + 10), p));
    }

    float mappingJoin(float body, float singular, float exclusion, float fade) {
        float weight = clamp((singular - exclusion) / fade, 0.0f, 1.0f);
        float solid = singular - exclusion;
        if (weight >= 1.0f) { return body; }
        return weight <= 0.0f ? solid : weight * body + (1.0f - weight) * solid;
    }
    """
}
