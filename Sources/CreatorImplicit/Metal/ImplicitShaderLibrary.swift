/// The Metal Shading Language every compiled implicit shares (implicit spec §4.1): the distance functions of the primitives, the smooth
/// minimum, the lookup into baked distance blocks, simplex noise and picture sampling. Each is a line-for-line port of its CPU twin
/// (`CPUEvaluation`, `DistanceBlocks.value(at:)`, `FieldNoise`, `GreyImage.value`), and the agreement suite holds the two to 1e-4 mm.
///
/// Data reaches a shader through five buffers: `P` (float parameters), `I` (integer parameters), `tables` (block tables and noise
/// seeds), `pool` (block samples) and `images` (pixels). A compiled tree's source names slots in them but never holds a number, so
/// editing a value changes the buffers and not the source.
enum ImplicitShaderLibrary {
    static let source = core + "\n\n" + lattices

    /// Everything but the lattices (`ImplicitShaderLibrary+Lattices`).
    static let core = """
    #include <metal_stdlib>
    using namespace metal;

    struct Env {
        device const float* P;
        device const int* I;
        device const int* tables;
        device const float* pool;
        device const float* images;
    };

    inline float smoothMin(float a, float b, float k) {
        if (!(k > 0.0)) { return min(a, b); }
        float blend = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - blend * blend * k * 0.25;
    }

    inline float sdBox(float3 p, float3 halfSize, float r) {
        float3 q = abs(p) - (halfSize - r);
        return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
    }

    inline float regionDistance(float3 p, float3 centre, float3 halfSize) {
        float3 q = abs(p - centre) - halfSize;
        return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
    }

    inline float sdCylinder(float3 p, float r, float halfHeight) {
        float across = length(p.xy) - r;
        float along = abs(p.z) - halfHeight;
        return min(max(across, along), 0.0) + length(max(float2(across, along), 0.0));
    }

    // MARK: baked distance blocks (DistanceBlocks)

    inline float bakedSample(const thread Env& e, int ioff, int i, int j, int k) {
        int nx = e.I[ioff + 3], ny = e.I[ioff + 4], nz = e.I[ioff + 5];
        i = clamp(i, 0, nx * 8 - 1);
        j = clamp(j, 0, ny * 8 - 1);
        k = clamp(k, 0, nz * 8 - 1);
        int block = ((k / 8) * ny + (j / 8)) * nx + (i / 8);
        int slot = e.tables[e.I[ioff] + block];
        if (slot < 0) { return e.pool[e.I[ioff + 2] + block]; }
        return e.pool[e.I[ioff + 1] + slot * 512 + ((k % 8) * 8 + (j % 8)) * 8 + (i % 8)];
    }

    // The trilinear value at a point already held to the grid.
    inline float bakedTrilinear(const thread Env& e, int ioff, int poff, float3 held) {
        float3 origin = float3(e.P[poff], e.P[poff + 1], e.P[poff + 2]);
        float spacing = e.P[poff + 3];
        float3 last = float3(e.I[ioff + 3] * 8 - 1, e.I[ioff + 4] * 8 - 1, e.I[ioff + 5] * 8 - 1);
        float3 grid = clamp((held - origin) / spacing, float3(0.0), last);
        int ix = int(floor(grid.x)), iy = int(floor(grid.y)), iz = int(floor(grid.z));
        float tx = grid.x - float(ix), ty = grid.y - float(iy), tz = grid.z - float(iz);
        float x00 = mix(bakedSample(e, ioff, ix, iy, iz), bakedSample(e, ioff, ix + 1, iy, iz), tx);
        float x10 = mix(bakedSample(e, ioff, ix, iy + 1, iz), bakedSample(e, ioff, ix + 1, iy + 1, iz), tx);
        float x01 = mix(bakedSample(e, ioff, ix, iy, iz + 1), bakedSample(e, ioff, ix + 1, iy, iz + 1), tx);
        float x11 = mix(bakedSample(e, ioff, ix, iy + 1, iz + 1), bakedSample(e, ioff, ix + 1, iy + 1, iz + 1), tx);
        return mix(mix(x00, x10, ty), mix(x01, x11, ty), tz);
    }

    // DistanceBlocks.value(at:): the trilinear value at the point held to the grid, and the distance to the grid added.
    inline float bakedValue(const thread Env& e, int ioff, int poff, float3 point) {
        float3 origin = float3(e.P[poff], e.P[poff + 1], e.P[poff + 2]);
        float3 last = float3(e.I[ioff + 3] * 8 - 1, e.I[ioff + 4] * 8 - 1, e.I[ioff + 5] * 8 - 1);
        float3 held = clamp(point, origin, origin + last * e.P[poff + 3]);
        return bakedTrilinear(e, ioff, poff, held) + length(point - held);
    }

    // DistanceBlocks.channelValue(at:): the same, with nothing added for the distance (a face chart's coordinates).
    inline float bakedChannel(const thread Env& e, int ioff, int poff, float3 point) {
        float3 origin = float3(e.P[poff], e.P[poff + 1], e.P[poff + 2]);
        float3 last = float3(e.I[ioff + 3] * 8 - 1, e.I[ioff + 4] * 8 - 1, e.I[ioff + 5] * 8 - 1);
        return bakedTrilinear(e, ioff, poff, clamp(point, origin, origin + last * e.P[poff + 3]));
    }

    // MARK: field maths

    inline float remapField(float x, float fromLow, float fromHigh, float toLow, float toHigh, int clamped) {
        if (fromHigh == fromLow) { return toLow; }
        float mapped = toLow + (x - fromLow) / (fromHigh - fromLow) * (toHigh - toLow);
        if (clamped == 0) { return mapped; }
        return min(max(mapped, min(toLow, toHigh)), max(toLow, toHigh));
    }

    // MARK: simplex noise (FieldNoise)

    constant float3 noiseGradients[12] = {
        float3(1, 1, 0), float3(-1, 1, 0), float3(1, -1, 0), float3(-1, -1, 0), float3(1, 0, 1), float3(-1, 0, 1),
        float3(1, 0, -1), float3(-1, 0, -1), float3(0, 1, 1), float3(0, -1, 1), float3(0, 1, -1), float3(0, -1, -1)
    };

    constant int3 noiseCorners[24] = {
        int3(0, 0, 0), int3(1, 0, 0), int3(1, 1, 0), int3(1, 1, 1),
        int3(0, 0, 0), int3(1, 0, 0), int3(1, 0, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 0, 1), int3(1, 0, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 0, 1), int3(0, 1, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 1, 0), int3(0, 1, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 1, 0), int3(1, 1, 0), int3(1, 1, 1)
    };

    inline ulong mix64(ulong value) {
        ulong z = value;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    inline float3 noiseGradient(int i, int j, int k, ulong start) {
        ulong packed = (ulong(i & 0x1FFFFF) << 42) | (ulong(j & 0x1FFFFF) << 21) | ulong(k & 0x1FFFFF);
        ulong draw = mix64(start + (packed + 1) * 0x9E3779B97F4A7C15UL);
        return noiseGradients[uint(draw >> 33) % 12];
    }

    inline float simplexOctave(float x, float y, float z, ulong start) {
        float skewed = (x + y + z) * (1.0 / 3.0);
        int i = int(floor(x + skewed)), j = int(floor(y + skewed)), k = int(floor(z + skewed));
        float back = float(i + j + k) * (1.0 / 6.0);
        float x0 = x - (float(i) - back), y0 = y - (float(j) - back), z0 = z - (float(k) - back);
        int ordering;
        if (x0 >= y0) {
            ordering = y0 >= z0 ? 0 : (x0 >= z0 ? 1 : 2);
        } else {
            ordering = y0 < z0 ? 3 : (x0 < z0 ? 4 : 5);
        }
        float sum = 0.0;
        for (int step = 0; step < 4; step++) {
            int3 corner = noiseCorners[ordering * 4 + step];
            float shift = float(step) * (1.0 / 6.0);
            float dx = x0 - float(corner.x) + shift, dy = y0 - float(corner.y) + shift, dz = z0 - float(corner.z) + shift;
            float falloff = 0.6 - dx * dx - dy * dy - dz * dz;
            if (falloff <= 0.0) { continue; }
            float3 gradient = noiseGradient(i + corner.x, j + corner.y, k + corner.z, start);
            float weight = falloff * falloff;
            sum += weight * weight * dot(gradient, float3(dx, dy, dz));
        }
        return 32.0 * sum;
    }

    inline float fieldNoise(const thread Env& e, float3 p, float scale, int octaves, int seeds) {
        float sum = 0.0, total = 0.0, amplitude = 1.0, size = scale;
        for (int octave = 0; octave < octaves; octave++) {
            ulong start = ulong(uint(e.tables[seeds + 2 * octave])) | (ulong(uint(e.tables[seeds + 2 * octave + 1])) << 32);
            sum += amplitude * simplexOctave(p.x / size, p.y / size, p.z / size, start);
            total += amplitude;
            amplitude *= 0.5;
            size *= 0.5;
        }
        return clamp((sum / total + 1.0) / 2.0, 0.0, 1.0);
    }

    // MARK: pictures (GreyImage)

    inline void imageTaps(float position, int count, int edges, thread int& low, thread int& high, thread float& fraction) {
        float size = float(count);
        float held;
        if (edges == 0) {
            float folded = position - floor(position / size) * size;
            held = min(max(folded, 0.0), as_type<float>(as_type<uint>(size) - 1u));
            low = int(floor(held));
            high = (low + 1) % count;
        } else {
            held = min(max(position, 0.0), size - 1.0);
            low = int(floor(held));
            high = min(low + 1, count - 1);
        }
        fraction = held - float(low);
    }

    inline float imageValue(const thread Env& e, int ioff, float u, float v) {
        int offset = e.I[ioff], width = e.I[ioff + 1], height = e.I[ioff + 2], edges = e.I[ioff + 3];
        float x = u * float(width) - 0.5, y = v * float(height) - 0.5;
        if (!isfinite(x) || !isfinite(y)) { return 0.0; }
        int cl, ch, rl, rh;
        float cf, rf;
        imageTaps(x, width, edges, cl, ch, cf);
        imageTaps(y, height, edges, rl, rh, rf);
        float top = mix(e.images[offset + rl * width + cl], e.images[offset + rl * width + ch], cf);
        float bottom = mix(e.images[offset + rh * width + cl], e.images[offset + rh * width + ch], cf);
        return mix(top, bottom, rf) / 65535.0;
    }
    """
}
