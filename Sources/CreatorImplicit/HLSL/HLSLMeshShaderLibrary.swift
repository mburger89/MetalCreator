/// The meshing kernels in HLSL (plan xp-c; implicit spec §4.3, Errata D13): the twin of `ImplicitMeshShaderLibrary`, one source per kernel (SDL_GPU
/// compiles one entry point a shader), and `mesh_clear`, which empties the edge table because SDL_GPU has no buffer fill. The order of vertices and
/// triangles is the threads', as on Metal; the set is fixed.
enum HLSLMeshShaderLibrary {
    /// The table's hash and the lattice edge key (shared by classify, emit and place).
    static let common = """

    uint tableHash(uint key, uint mask) {
        uint h = key * 0x9E3779B1u;
        h ^= h >> 16;
        h *= 0x85EBCA6Bu;
        h ^= h >> 13;
        return h & mask;
    }

    uint edgeKeyOf(uint x, uint y, uint z, uint a, uint b) {
        uint lx = x + (a & 1u), ly = y + ((a >> 1) & 1u), lz = z + ((a >> 2) & 1u);
        uint axis = ((a ^ b) == 1u) ? 0u : (((a ^ b) == 2u) ? 1u : 2u);
        return ((lz * gNY + ly) * gNX + lx) * 3u + axis;
    }

    """

    /// A cube's corners and pattern (classify, emit; after `samples` is declared).
    static let cubes = """

    float cornerValue(uint base, uint x, uint y, uint z, uint corner) {
        return samples[base + ((z + (corner >> 2)) * SIDE + y + ((corner >> 1) & 1u)) * SIDE + x + (corner & 1u)];
    }

    uint cubePattern(uint base, uint x, uint y, uint z) {
        uint pattern = 0u;
        for (uint corner = 0u; corner < 8u; ++corner) {
            if (cornerValue(base, x, y, z, corner) < 0.0f) { pattern |= 1u << corner; }
        }
        return pattern;
    }

    """

    /// A lattice point at the CPU's coordinates (sample, place; after `axes` is declared).
    static let latticePoint = """

    float3 latticePoint(uint x, uint y, uint z) {
        return float3(axes[x], axes[gNX + y], axes[gNX + gNY + z]);
    }

    """

    static let clear = """

    RWStructuredBuffer<uint> keys : register(u0, space1);

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint slot = gFirstSlot + id.x;
        if (id.x >= gCount || slot > gMask) { return; }
        keys[slot] = EMPTY_KEY;
    }
    """

    static let sample = """

    StructuredBuffer<uint> bricks : register(t2, space0);
    StructuredBuffer<float> axes : register(t3, space0);
    RWStructuredBuffer<float> samples : register(u0, space1);
    """ + latticePoint + """

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        if (buffersAreKept()) { return; }
        if (gPadding0 == 0xFFFFFFFFu && float(bricks[0]) + axes[0] == 0.0f) { return; }
        uint gid = id.x;
        if (gid >= gBrickCount * POINTS) { return; }
        uint b = gid / POINTS, r = gid % POINTS;
        uint x = r % SIDE, y = (r / SIDE) % SIDE, z = r / (SIDE * SIDE);
        uint at = (gFirstBrick + b) * 3u;
        samples[gid] = sdf(latticePoint(bricks[at] * BRICK + x, bricks[at + 1u] * BRICK + y, bricks[at + 2u] * BRICK + z));
    }
    """

    static let classify = """

    StructuredBuffer<uint> bricks : register(t0, space0);
    StructuredBuffer<float> samples : register(t1, space0);
    StructuredBuffer<uint> cubeTable : register(t2, space0);
    RWStructuredBuffer<uint> keys : register(u0, space1);
    RWStructuredBuffer<uint> counters : register(u1, space1);
    """ + common + cubes + """

    void claimSlot(uint key) {
        uint slot = tableHash(key, gMask);
        for (uint probe = 0u; probe < PROBE_LIMIT; ++probe) {
            uint original;
            InterlockedCompareExchange(keys[slot], EMPTY_KEY, key, original);
            if (original == EMPTY_KEY || original == key) { return; }
            slot = (slot + 1u) & gMask;
        }
        InterlockedOr(counters[COUNTER_OVERFLOW], 1u);
    }

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint gid = id.x;
        if (gid >= gBrickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        InterlockedAdd(counters[COUNTER_TRIANGLE_TOTAL], (end - begin) / 3u);
        uint at = (gFirstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        for (uint edge = 0u; edge < 12u; ++edge) {
            uint low = cubeTable[CUBE_LOWER + edge], high = cubeTable[CUBE_UPPER + edge];
            if (((pattern >> low) & 1u) != ((pattern >> high) & 1u)) {
                claimSlot(edgeKeyOf(lx, ly, lz, low, high));
            }
        }
    }
    """

    static let number = """

    StructuredBuffer<uint> keys : register(t0, space0);
    RWStructuredBuffer<uint> slotVertex : register(u0, space1);
    RWStructuredBuffer<uint> counters : register(u1, space1);

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint slot = gFirstSlot + id.x;
        if (id.x >= gCount || slot > gMask || keys[slot] == EMPTY_KEY) { return; }
        uint vertexNumber;
        InterlockedAdd(counters[COUNTER_VERTICES], 1u, vertexNumber);
        slotVertex[slot] = vertexNumber;
    }
    """

    static let place = """

    StructuredBuffer<float> axes : register(t2, space0);
    StructuredBuffer<uint> keys : register(t3, space0);
    StructuredBuffer<uint> slotVertex : register(t4, space0);
    RWStructuredBuffer<float4> positions : register(u0, space1);
    RWStructuredBuffer<float4> normals : register(u1, space1);
    """ + latticePoint + """

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        if (buffersAreKept()) { return; }
        uint slot = gFirstSlot + id.x;
        if (id.x >= gCount || slot > gMask) { return; }
        uint key = keys[slot];
        if (key == EMPTY_KEY) { return; }
        uint axis = key % 3u, index = key / 3u;
        uint x = index % gNX, y = (index / gNX) % gNY, z = index / (gNX * gNY);
        float3 low = latticePoint(x, y, z);
        float3 high = latticePoint(x + (axis == 0u ? 1u : 0u), y + (axis == 1u ? 1u : 0u), z + (axis == 2u ? 1u : 0u));
        float fa = sdf(low), fb = sdf(high);
        float t = fa / (fa - fb);
        float3 position = low;
        if (axis == 0u) {
            position.x = low.x + gResolution * t;
        } else if (axis == 1u) {
            position.y = low.y + gResolution * t;
        } else {
            position.z = low.z + gResolution * t;
        }
        float3 normal = float3(0.0f, 0.0f, 0.0f);
        if (gSnap != 0u) {
            float delta = gResolution / 4.0f, limit = gResolution / 2.0f;
            float value = sdf(position);
            float3 gradient = float3(
                (sdf(position + float3(delta, 0.0f, 0.0f)) - sdf(position - float3(delta, 0.0f, 0.0f))) / (2.0f * delta),
                (sdf(position + float3(0.0f, delta, 0.0f)) - sdf(position - float3(0.0f, delta, 0.0f))) / (2.0f * delta),
                (sdf(position + float3(0.0f, 0.0f, delta)) - sdf(position - float3(0.0f, 0.0f, delta))) / (2.0f * delta));
            float squared = dot(gradient, gradient);
            if (squared > 1e-12f) {
                normal = gradient / sqrt(squared);
                float3 move = gradient * (-value / squared);
                float moved = sqrt(dot(move, move));
                if (moved > limit) { move *= limit / moved; }
                position += move;
            }
        }
        uint vertexNumber = slotVertex[slot];
        positions[vertexNumber] = float4(position, 0.0f);
        normals[vertexNumber] = float4(normal, 0.0f);
    }
    """

    static let emit = """

    StructuredBuffer<uint> bricks : register(t0, space0);
    StructuredBuffer<float> samples : register(t1, space0);
    StructuredBuffer<uint> cubeTable : register(t2, space0);
    StructuredBuffer<uint> keys : register(t3, space0);
    StructuredBuffer<uint> slotVertex : register(t4, space0);
    RWStructuredBuffer<uint> counters : register(u0, space1);
    RWStructuredBuffer<uint> indices : register(u1, space1);
    """ + common + cubes + """

    uint vertexOfKey(uint key) {
        uint slot = tableHash(key, gMask);
        for (uint probe = 0u; probe <= gMask; ++probe) {
            if (keys[slot] == key) { return slotVertex[slot]; }
            slot = (slot + 1u) & gMask;
        }
        return 0u;
    }

    [numthreads(64, 1, 1)]
    void main(uint3 id : SV_DispatchThreadID) {
        uint gid = id.x;
        if (gid >= gBrickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        uint at = (gFirstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        uint place;
        InterlockedAdd(counters[COUNTER_TRIANGLE_CURSOR], (end - begin) / 3u, place);
        for (uint corner = 0u; corner < end - begin; ++corner) {
            uint edge = cubeTable[CUBE_EDGES + begin + corner];
            indices[place * 3u + corner] = vertexOfKey(edgeKeyOf(lx, ly, lz, cubeTable[CUBE_LOWER + edge], cubeTable[CUBE_UPPER + edge]));
        }
    }
    """
}
