/// The meshing kernels of a GPU engine (implicit spec §4.3, Errata D13), as Metal Shading Language text appended to a
/// `CompiledImplicit`'s source so they call its `sdf`. Text only: it imports nothing and builds everywhere, and an SDL3 engine (track
/// xp-c) translates it, as it will the evaluator's source. Every kernel is a line-for-line port of the CPU mesher (`MeshBuilder`,
/// `ImplicitMesher.snap`) and reads the same `MarchingCubesTable` through `MarchingCubesBuffers`.
///
/// One mesh is five dispatches over a shared table of edge keys (`BrickLattice`'s numbering):
/// 1. `meshSample`, per lattice point of a batch of bricks: the solid's value, at the CPU's coordinates;
/// 2. `meshClassify`, per cube: its pattern; adds its triangles to the total; claims a table slot for each lattice edge it crosses
///    (compare and swap on the key, so an edge shared by four cubes, or by two bricks, is one slot);
///    steps 1 and 2 run for every batch before step 3, so the table holds every edge;
/// 3. `meshNumber`, per table slot: the slot's vertex number;
/// 4. `meshPlace`, per table slot: the vertex on its edge by linear interpolation, then the Newton step and the normal; steps 3 and 4
///    run over the table in ranges of slots (`MeshParams.firstSlot`), a command buffer each, so no one buffer holds millions of
///    evaluations of a heavy `sdf` (the GPU's watchdog) and a cancel can end a mesh between them;
/// 5. `meshEmit`, per cube (samples again, per batch): its triangles, each corner the vertex of its edge's slot, at a place in the
///    index buffer taken from an atomic cursor.
///
/// Slots and cursor places are taken in whatever order the threads run, so the *order* of vertices and triangles differs from run to
/// run; the set does not.
enum ImplicitMeshShaderLibrary {
    /// Buffer indices every kernel shares. A kernel declares the ones it reads.
    enum Binding {
        static let bricks = 0
        static let axes = 1
        static let samples = 2
        static let parameters = 3, integers = 4, tables = 5, pool = 6, images = 7
        static let meshParameters = 8
        static let cubeTable = 9
        static let keys = 10
        static let slotVertex = 11
        static let counters = 12
        static let positions = 13
        static let normals = 14
        static let indices = 15
    }

    /// Indices into the counters buffer.
    enum Counter {
        /// Vertices numbered by `meshNumber`.
        static let vertices = 0
        /// Triangles `meshClassify` found, over every batch.
        static let triangleTotal = 1
        /// The next free triangle of the index buffer.
        static let triangleCursor = 2
        /// Set when a key found no slot within `probeLimit` steps: the table is too small.
        static let overflow = 3
        static let count = 4
    }

    /// The longest run of occupied slots a key will walk past before the table is called too small.
    static let probeLimit = 128

    /// The kernels' names, in the order of the five steps.
    static let kernelNames = ["meshSample", "meshClassify", "meshNumber", "meshPlace", "meshEmit"]

    /// The Metal source of `program` with the meshing kernels added.
    static func source(extending program: CompiledImplicit) -> String {
        program.source + "\n" + kernels
    }

    private static let kernels = """
    struct MeshParams {
        uint firstBrick;
        uint brickCount;
        uint nx;
        uint ny;
        uint nz;
        uint mask;
        uint snap;
        float resolution;
        uint firstSlot;
    };

    constant uint EMPTY_KEY = 0xFFFFFFFFu;
    constant uint CUBE_STARTS = \(MarchingCubesBuffers.startsOffset)u;
    constant uint CUBE_LOWER = \(MarchingCubesBuffers.lowerCornersOffset)u;
    constant uint CUBE_UPPER = \(MarchingCubesBuffers.upperCornersOffset)u;
    constant uint CUBE_EDGES = \(MarchingCubesBuffers.edgesOffset)u;
    constant uint BRICK = \(BrickPlan.brickSize)u;
    constant uint SIDE = \(BrickPlan.brickSize + 1)u;
    constant uint CUBES = \(BrickPlan.brickSize * BrickPlan.brickSize * BrickPlan.brickSize)u;
    constant uint POINTS = \((BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1))u;

    inline uint tableHash(uint key, uint mask) {
        uint h = key * 0x9E3779B1u;
        h ^= h >> 16;
        h *= 0x85EBCA6Bu;
        h ^= h >> 13;
        return h & mask;
    }

    inline float3 latticePoint(device const float* axes, constant MeshParams& m, uint x, uint y, uint z) {
        return float3(axes[x], axes[m.nx + y], axes[m.nx + m.ny + z]);
    }

    // The key of the edge between corners a and b of the cube whose lowest lattice point is (x, y, z): the CPU's formula.
    inline uint edgeKey(constant MeshParams& m, uint x, uint y, uint z, uint a, uint b) {
        uint lx = x + (a & 1u), ly = y + ((a >> 1) & 1u), lz = z + ((a >> 2) & 1u);
        uint axis = ((a ^ b) == 1u) ? 0u : (((a ^ b) == 2u) ? 1u : 2u);
        return ((lz * m.ny + ly) * m.nx + lx) * 3u + axis;
    }

    inline float cornerValue(device const float* samples, uint base, uint x, uint y, uint z, uint corner) {
        return samples[base + ((z + (corner >> 2)) * SIDE + y + ((corner >> 1) & 1u)) * SIDE + x + (corner & 1u)];
    }

    inline uint cubePattern(device const float* samples, uint base, uint x, uint y, uint z) {
        uint pattern = 0u;
        for (uint corner = 0u; corner < 8u; ++corner) {
            if (cornerValue(samples, base, x, y, z, corner) < 0.0) { pattern |= 1u << corner; }
        }
        return pattern;
    }

    inline void claimSlot(device atomic_uint* keys, device atomic_uint* counters, uint mask, uint key) {
        uint slot = tableHash(key, mask);
        for (uint probe = 0u; probe < \(probeLimit)u; ++probe) {
            uint expected = EMPTY_KEY;
            bool won = atomic_compare_exchange_weak_explicit(&keys[slot], &expected, key,
                                                             memory_order_relaxed, memory_order_relaxed);
            if (won || expected == key) { return; }
            // A spurious failure leaves the slot empty: try it again. Otherwise it holds another key: go on.
            if (expected != EMPTY_KEY) { slot = (slot + 1u) & mask; }
        }
        atomic_store_explicit(&counters[\(Counter.overflow)], 1u, memory_order_relaxed);
    }

    inline uint vertexOfKey(device const uint* keys, device const uint* slotVertex, uint mask, uint key) {
        uint slot = tableHash(key, mask);
        for (uint probe = 0u; probe <= mask; ++probe) {
            if (keys[slot] == key) { return slotVertex[slot]; }
            slot = (slot + 1u) & mask;
        }
        return 0u;
    }

    kernel void meshSample(device const uint* bricks [[buffer(\(Binding.bricks))]],
                           device const float* axes [[buffer(\(Binding.axes))]],
                           device float* samples [[buffer(\(Binding.samples))]],
                           device const float* P [[buffer(\(Binding.parameters))]],
                           device const int* I [[buffer(\(Binding.integers))]],
                           device const int* tables [[buffer(\(Binding.tables))]],
                           device const float* pool [[buffer(\(Binding.pool))]],
                           device const float* images [[buffer(\(Binding.images))]],
                           constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                           uint gid [[thread_position_in_grid]]) {
        if (gid >= m.brickCount * POINTS) { return; }
        uint b = gid / POINTS, r = gid % POINTS;
        uint x = r % SIDE, y = (r / SIDE) % SIDE, z = r / (SIDE * SIDE);
        uint at = (m.firstBrick + b) * 3u;
        Env e = { P, I, tables, pool, images };
        float3 point = latticePoint(axes, m, bricks[at] * BRICK + x, bricks[at + 1u] * BRICK + y, bricks[at + 2u] * BRICK + z);
        samples[gid] = sdf(e, point);
    }

    kernel void meshClassify(device const uint* bricks [[buffer(\(Binding.bricks))]],
                             device const float* samples [[buffer(\(Binding.samples))]],
                             constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                             device const uint* cubeTable [[buffer(\(Binding.cubeTable))]],
                             device atomic_uint* keys [[buffer(\(Binding.keys))]],
                             device atomic_uint* counters [[buffer(\(Binding.counters))]],
                             uint gid [[thread_position_in_grid]]) {
        if (gid >= m.brickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(samples, b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        atomic_fetch_add_explicit(&counters[\(Counter.triangleTotal)], (end - begin) / 3u, memory_order_relaxed);
        uint at = (m.firstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        for (uint edge = 0u; edge < 12u; ++edge) {
            uint low = cubeTable[CUBE_LOWER + edge], high = cubeTable[CUBE_UPPER + edge];
            if (((pattern >> low) & 1u) != ((pattern >> high) & 1u)) {
                claimSlot(keys, counters, m.mask, edgeKey(m, lx, ly, lz, low, high));
            }
        }
    }

    kernel void meshNumber(constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                           device const uint* keys [[buffer(\(Binding.keys))]],
                           device uint* slotVertex [[buffer(\(Binding.slotVertex))]],
                           device atomic_uint* counters [[buffer(\(Binding.counters))]],
                           uint gid [[thread_position_in_grid]]) {
        uint slot = m.firstSlot + gid;
        if (slot > m.mask || keys[slot] == EMPTY_KEY) { return; }
        slotVertex[slot] = atomic_fetch_add_explicit(&counters[\(Counter.vertices)], 1u, memory_order_relaxed);
    }

    kernel void meshPlace(device const float* axes [[buffer(\(Binding.axes))]],
                          device const float* P [[buffer(\(Binding.parameters))]],
                          device const int* I [[buffer(\(Binding.integers))]],
                          device const int* tables [[buffer(\(Binding.tables))]],
                          device const float* pool [[buffer(\(Binding.pool))]],
                          device const float* images [[buffer(\(Binding.images))]],
                          constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                          device const uint* keys [[buffer(\(Binding.keys))]],
                          device const uint* slotVertex [[buffer(\(Binding.slotVertex))]],
                          device float4* positions [[buffer(\(Binding.positions))]],
                          device float4* normals [[buffer(\(Binding.normals))]],
                          uint gid [[thread_position_in_grid]]) {
        uint slot = m.firstSlot + gid;
        if (slot > m.mask) { return; }
        uint key = keys[slot];
        if (key == EMPTY_KEY) { return; }
        uint axis = key % 3u, index = key / 3u;
        uint x = index % m.nx, y = (index / m.nx) % m.ny, z = index / (m.nx * m.ny);
        Env e = { P, I, tables, pool, images };
        float3 low = latticePoint(axes, m, x, y, z);
        float3 high = latticePoint(axes, m, x + (axis == 0u ? 1u : 0u), y + (axis == 1u ? 1u : 0u),
                                   z + (axis == 2u ? 1u : 0u));
        float fa = sdf(e, low), fb = sdf(e, high);
        // Equal endpoint values (a surface lying on a lattice plane) must not divide 0/0 or x/0.
        float span = fa - fb;
        float t = span != 0.0 ? fa / span : 0.5;
        t = isfinite(t) ? clamp(t, 0.0, 1.0) : 0.5;
        float3 position = low;
        position[axis] = low[axis] + m.resolution * t;
        float3 normal = float3(0.0);
        if (m.snap != 0u) {
            float delta = m.resolution / 4.0, limit = m.resolution / 2.0;
            float value = sdf(e, position);
            float3 gradient = float3(
                (sdf(e, position + float3(delta, 0.0, 0.0)) - sdf(e, position - float3(delta, 0.0, 0.0))) / (2.0 * delta),
                (sdf(e, position + float3(0.0, delta, 0.0)) - sdf(e, position - float3(0.0, delta, 0.0))) / (2.0 * delta),
                (sdf(e, position + float3(0.0, 0.0, delta)) - sdf(e, position - float3(0.0, 0.0, delta))) / (2.0 * delta));
            float squared = dot(gradient, gradient);
            if (squared > 1e-12) {
                normal = gradient / sqrt(squared);
                float3 move = gradient * (-value / squared);
                float moved = sqrt(dot(move, move));
                if (moved > limit) { move *= limit / moved; }
                position += move;
            }
        }
        uint number = slotVertex[slot];
        positions[number] = float4(position, 0.0);
        normals[number] = float4(normal, 0.0);
    }

    kernel void meshEmit(device const uint* bricks [[buffer(\(Binding.bricks))]],
                         device const float* samples [[buffer(\(Binding.samples))]],
                         constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                         device const uint* cubeTable [[buffer(\(Binding.cubeTable))]],
                         device const uint* keys [[buffer(\(Binding.keys))]],
                         device const uint* slotVertex [[buffer(\(Binding.slotVertex))]],
                         device atomic_uint* counters [[buffer(\(Binding.counters))]],
                         device uint* indices [[buffer(\(Binding.indices))]],
                         uint gid [[thread_position_in_grid]]) {
        if (gid >= m.brickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(samples, b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        uint at = (m.firstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        uint place = atomic_fetch_add_explicit(&counters[\(Counter.triangleCursor)], (end - begin) / 3u, memory_order_relaxed);
        uint first = place * 3u;
        for (uint corner = 0u; corner < end - begin; ++corner) {
            uint edge = cubeTable[CUBE_EDGES + begin + corner];
            uint key = edgeKey(m, lx, ly, lz, cubeTable[CUBE_LOWER + edge], cubeTable[CUBE_UPPER + edge]);
            indices[first + corner] = vertexOfKey(keys, slotVertex, m.mask, key);
        }
    }
    """
}
