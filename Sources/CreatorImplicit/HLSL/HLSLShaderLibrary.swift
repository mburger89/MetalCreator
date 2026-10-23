/// The HLSL every compiled implicit shares (plan xp-c): the twin of `ImplicitShaderLibrary` (MSL), function for function, with the
/// engine's own
/// trigonometry (`+Math`) and the lattices (`+Lattices`). Text only: it imports nothing and builds everywhere. The buffers are two
/// globals, `floats`
/// (the parameters, then the pool, then the pictures) and `ints` (the integer parameters, then the tables), read through `P`, `I`,
/// `POOL`, `IMAGES`
/// and `TABLES`, so the generated `sdf` names a parameter `P(k)` where Metal's names `e.P[k]`.
enum HLSLShaderLibrary {
    /// Every kernel's start: the constants the Swift side shares and the uniform block (`KernelParameters`, word for word).
    static let prelude = """
    #define THREADS 64
    #define EMPTY_KEY 0xFFFFFFFFu
    #define CUBE_STARTS \(MarchingCubesBuffers.startsOffset)u
    #define CUBE_LOWER \(MarchingCubesBuffers.lowerCornersOffset)u
    #define CUBE_UPPER \(MarchingCubesBuffers.upperCornersOffset)u
    #define CUBE_EDGES \(MarchingCubesBuffers.edgesOffset)u
    #define BRICK \(BrickPlan.brickSize)u
    #define SIDE \(BrickPlan.brickSize + 1)u
    #define CUBES \(BrickPlan.brickSize * BrickPlan.brickSize * BrickPlan.brickSize)u
    #define POINTS \((BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1))u
    #define PROBE_LIMIT \(ImplicitMeshShaderLibrary.probeLimit)u
    #define COUNTER_VERTICES \(ImplicitMeshShaderLibrary.Counter.vertices)u
    #define COUNTER_TRIANGLE_TOTAL \(ImplicitMeshShaderLibrary.Counter.triangleTotal)u
    #define COUNTER_TRIANGLE_CURSOR \(ImplicitMeshShaderLibrary.Counter.triangleCursor)u
    #define COUNTER_OVERFLOW \(ImplicitMeshShaderLibrary.Counter.overflow)u
    #define INFINITY_F asfloat(0x7F800000u)
    #define PI_F 3.14159265358979323846f
    #define HALF_PI_F 1.57079632679489661923f
    #define QUARTER_PI_F 0.78539816339744830962f

    cbuffer Params : register(b0, space2) {
        uint gCount;
        uint gPoolBase;
        uint gImagesBase;
        uint gTablesBase;
        uint gFirstBrick;
        uint gBrickCount;
        uint gNX;
        uint gNY;
        uint gNZ;
        uint gMask;
        uint gSnap;
        float gResolution;
        uint gFirstSlot;
        uint gPadding0;
        uint gPadding1;
        uint gPadding2;
    };

    """

    /// For a kernel that calls `sdf`: the packed buffers (always slots 0 and 1), the library and the shape's `sdf`.
    static func withSDF(_ sdf: String) -> String {
        """
        StructuredBuffer<float> floats : register(t0, space0);
        StructuredBuffer<int> ints : register(t1, space0);

        """ + math + "\n" + core + "\n" + keepBuffers + "\n" + lattices + "\n" + sdf
    }

    /// DXC drops a declared buffer nothing reads, and the slots after it shift. A `.sphere` never reads `ints` and an empty union reads
    /// neither packed buffer, so every `main` begins with `if (buffersAreKept()) { return; }`: a read of both, behind a Params word
    /// the host never sets (`gPadding0` is always 0) and which the compiler cannot see through, so the loads stay and the branch is
    /// never taken. A solid whose `sdf` ignores its point (an empty union) also drops the kernel's own input buffer, so `evaluate` and `sample`
    /// read theirs behind the same word.
    static let keepBuffers = """
    bool buffersAreKept() {
        return gPadding0 == 0xFFFFFFFFu && floats[0] + float(ints[0]) == 0.0f;
    }
    """

    /// Metal's `evaluateImplicit`: the solid at a batch of points, three floats each.
    static let evaluate = """

    StructuredBuffer<float> points : register(t2, space0);
    RWStructuredBuffer<float> values : register(u0, space1);

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        if (buffersAreKept()) { return; }
        if (gPadding0 == 0xFFFFFFFFu && points[0] == 0.0f) { return; }
        uint index = id.x;
        if (index >= gCount) { return; }
        values[index] = sdf(float3(points[3u * index], points[3u * index + 1u], points[3u * index + 2u]));
    }
    """

    /// `ImplicitShaderLibrary.core`, ported: primitives, smooth minimum, baked blocks, field maths, simplex noise, pictures.
    static let core = """
    // The functions every compiled implicit shares (implicit spec §4.1): a port of ImplicitShaderLibrary.core (the MSL of the Metal
    // engine), each a
    // line-for-line port of its CPU twin (CPUEvaluation, DistanceBlocks, FieldNoise, GreyImage). The kernel declares `floats` (the
    // parameters, then the
    // pool, then the pictures) and `ints` (the integer parameters, then the tables) before it includes this; the bases are in Params.

    float P(int k) { return floats[k]; }
    float3 PV(int k) { return float3(floats[k], floats[k + 1], floats[k + 2]); }
    int I(int k) { return ints[k]; }
    int TABLES(int k) { return ints[int(gTablesBase) + k]; }
    float POOL(int k) { return floats[int(gPoolBase) + k]; }
    float IMAGES(int k) { return floats[int(gImagesBase) + k]; }

    float smoothMin(float a, float b, float k) {
        if (!(k > 0.0f)) { return min(a, b); }
        float blend = max(k - abs(a - b), 0.0f) / k;
        return min(a, b) - blend * blend * k * 0.25f;
    }

    float sdBox(float3 p, float3 halfSize, float r) {
        float3 q = abs(p) - (halfSize - r);
        return length(max(q, 0.0f)) + min(max(q.x, max(q.y, q.z)), 0.0f) - r;
    }

    float regionDistance(float3 p, float3 centre, float3 halfSize) {
        float3 q = abs(p - centre) - halfSize;
        return length(max(q, 0.0f)) + min(max(q.x, max(q.y, q.z)), 0.0f);
    }

    float sdCylinder(float3 p, float r, float halfHeight) {
        float across = length(p.xy) - r;
        float along = abs(p.z) - halfHeight;
        return min(max(across, along), 0.0f) + length(max(float2(across, along), 0.0f));
    }

    // MARK: baked distance blocks (DistanceBlocks)

    float bakedSample(int ioff, int i, int j, int k) {
        int nx = I(ioff + 3), ny = I(ioff + 4), nz = I(ioff + 5);
        i = clamp(i, 0, nx * 8 - 1);
        j = clamp(j, 0, ny * 8 - 1);
        k = clamp(k, 0, nz * 8 - 1);
        int block = ((k / 8) * ny + (j / 8)) * nx + (i / 8);
        int slot = TABLES(I(ioff) + block);
        if (slot < 0) { return POOL(I(ioff + 2) + block); }
        return POOL(I(ioff + 1) + slot * 512 + ((k % 8) * 8 + (j % 8)) * 8 + (i % 8));
    }

    float bakedTrilinear(int ioff, int poff, float3 held) {
        float3 origin = PV(poff);
        float spacing = P(poff + 3);
        float3 last = float3(I(ioff + 3) * 8 - 1, I(ioff + 4) * 8 - 1, I(ioff + 5) * 8 - 1);
        float3 grid = clamp((held - origin) / spacing, float3(0.0f, 0.0f, 0.0f), last);
        int ix = int(floor(grid.x)), iy = int(floor(grid.y)), iz = int(floor(grid.z));
        float tx = grid.x - float(ix), ty = grid.y - float(iy), tz = grid.z - float(iz);
        float x00 = lerp(bakedSample(ioff, ix, iy, iz), bakedSample(ioff, ix + 1, iy, iz), tx);
        float x10 = lerp(bakedSample(ioff, ix, iy + 1, iz), bakedSample(ioff, ix + 1, iy + 1, iz), tx);
        float x01 = lerp(bakedSample(ioff, ix, iy, iz + 1), bakedSample(ioff, ix + 1, iy, iz + 1), tx);
        float x11 = lerp(bakedSample(ioff, ix, iy + 1, iz + 1), bakedSample(ioff, ix + 1, iy + 1, iz + 1), tx);
        return lerp(lerp(x00, x10, ty), lerp(x01, x11, ty), tz);
    }

    float bakedValue(int ioff, int poff, float3 at) {
        float3 origin = PV(poff);
        float3 last = float3(I(ioff + 3) * 8 - 1, I(ioff + 4) * 8 - 1, I(ioff + 5) * 8 - 1);
        float3 held = clamp(at, origin, origin + last * P(poff + 3));
        return bakedTrilinear(ioff, poff, held) + length(at - held);
    }

    float bakedChannel(int ioff, int poff, float3 at) {
        float3 origin = PV(poff);
        float3 last = float3(I(ioff + 3) * 8 - 1, I(ioff + 4) * 8 - 1, I(ioff + 5) * 8 - 1);
        return bakedTrilinear(ioff, poff, clamp(at, origin, origin + last * P(poff + 3)));
    }

    // MARK: field maths

    float remapField(float x, float fromLow, float fromHigh, float toLow, float toHigh, int clamped) {
        if (fromHigh == fromLow) { return toLow; }
        float mapped = toLow + (x - fromLow) / (fromHigh - fromLow) * (toHigh - toLow);
        if (clamped == 0) { return mapped; }
        return min(max(mapped, min(toLow, toHigh)), max(toLow, toHigh));
    }

    // MARK: simplex noise (FieldNoise)

    static const float3 noiseGradients[12] = {
        float3(1, 1, 0), float3(-1, 1, 0), float3(1, -1, 0), float3(-1, -1, 0), float3(1, 0, 1), float3(-1, 0, 1),
        float3(1, 0, -1), float3(-1, 0, -1), float3(0, 1, 1), float3(0, -1, 1), float3(0, 1, -1), float3(0, -1, -1)
    };

    static const int3 noiseCorners[24] = {
        int3(0, 0, 0), int3(1, 0, 0), int3(1, 1, 0), int3(1, 1, 1),
        int3(0, 0, 0), int3(1, 0, 0), int3(1, 0, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 0, 1), int3(1, 0, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 0, 1), int3(0, 1, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 1, 0), int3(0, 1, 1), int3(1, 1, 1),
        int3(0, 0, 0), int3(0, 1, 0), int3(1, 1, 0), int3(1, 1, 1)
    };

    U64 mix64(U64 value) {
        U64 z = value;
        z = u64Mul(u64Xor(z, u64Shr(z, 30u)), u64(0xBF58476Du, 0x1CE4E5B9u));
        z = u64Mul(u64Xor(z, u64Shr(z, 27u)), u64(0x94D049BBu, 0x133111EBu));
        return u64Xor(z, u64Shr(z, 31u));
    }

    float3 noiseGradient(int i, int j, int k, U64 start) {
        U64 packed = u64Or(u64Or(u64Shl(u64(0u, asuint(i) & 0x1FFFFFu), 42u), u64Shl(u64(0u, asuint(j) & 0x1FFFFFu), 21u)),
                           u64(0u, asuint(k) & 0x1FFFFFu));
        U64 draw = mix64(u64Add(start, u64Mul(u64Add(packed, u64(0u, 1u)), u64(0x9E3779B9u, 0x7F4A7C15u))));
        return noiseGradients[u64Shr(draw, 33u).lo % 12u];
    }

    float simplexOctave(float x, float y, float z, U64 start) {
        float skewed = (x + y + z) * (1.0f / 3.0f);
        int i = int(floor(x + skewed)), j = int(floor(y + skewed)), k = int(floor(z + skewed));
        float back = float(i + j + k) * (1.0f / 6.0f);
        float x0 = x - (float(i) - back), y0 = y - (float(j) - back), z0 = z - (float(k) - back);
        int ordering;
        if (x0 >= y0) {
            ordering = y0 >= z0 ? 0 : (x0 >= z0 ? 1 : 2);
        } else {
            ordering = y0 < z0 ? 3 : (x0 < z0 ? 4 : 5);
        }
        float sum = 0.0f;
        for (int step = 0; step < 4; step++) {
            int3 corner = noiseCorners[ordering * 4 + step];
            float shift = float(step) * (1.0f / 6.0f);
            float dx = x0 - float(corner.x) + shift, dy = y0 - float(corner.y) + shift, dz = z0 - float(corner.z) + shift;
            float falloff = 0.6f - dx * dx - dy * dy - dz * dz;
            if (falloff <= 0.0f) { continue; }
            float3 gradient = noiseGradient(i + corner.x, j + corner.y, k + corner.z, start);
            float weight = falloff * falloff;
            sum += weight * weight * dot(gradient, float3(dx, dy, dz));
        }
        return 32.0f * sum;
    }

    float fieldNoise(float3 p, float scale, int octaves, int seeds) {
        float sum = 0.0f, total = 0.0f, amplitude = 1.0f, size = scale;
        for (int octave = 0; octave < octaves; octave++) {
            U64 start = u64(asuint(TABLES(seeds + 2 * octave + 1)), asuint(TABLES(seeds + 2 * octave)));
            sum += amplitude * simplexOctave(p.x / size, p.y / size, p.z / size, start);
            total += amplitude;
            amplitude *= 0.5f;
            size *= 0.5f;
        }
        return clamp((sum / total + 1.0f) / 2.0f, 0.0f, 1.0f);
    }

    // MARK: pictures (GreyImage)

    void imageTaps(float position, int count, int edges, out int low, out int high, out float fraction) {
        float size = float(count);
        float held;
        if (edges == 0) {
            float folded = position - floor(position / size) * size;
            held = min(max(folded, 0.0f), asfloat(asuint(size) - 1u));
            low = int(floor(held));
            high = (low + 1) % count;
        } else {
            held = min(max(position, 0.0f), size - 1.0f);
            low = int(floor(held));
            high = min(low + 1, count - 1);
        }
        fraction = held - float(low);
    }

    float imageValue(int ioff, float u, float v) {
        int offset = I(ioff), width = I(ioff + 1), height = I(ioff + 2), edges = I(ioff + 3);
        float x = u * float(width) - 0.5f, y = v * float(height) - 0.5f;
        if (!isfinite(x) || !isfinite(y)) { return 0.0f; }
        int cl, ch, rl, rh;
        float cf, rf;
        imageTaps(x, width, edges, cl, ch, cf);
        imageTaps(y, height, edges, rl, rh, rf);
        float top = lerp(IMAGES(offset + rl * width + cl), IMAGES(offset + rl * width + ch), cf);
        float bottom = lerp(IMAGES(offset + rh * width + cl), IMAGES(offset + rh * width + ch), cf);
        return lerp(top, bottom, rf) / 65535.0f;
    }
    """
}
