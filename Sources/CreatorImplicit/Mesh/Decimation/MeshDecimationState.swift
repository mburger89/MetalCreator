/// The working state of one decimation (`MeshDecimator`): positions in `Double`, a quadric per vertex, the triangles around each
/// vertex, and the heap of candidate collapses. Vertices on an open edge are pinned: they never move and never go.
struct MeshDecimationState {
    var position: [SIMD3<Double>]
    var quadric: [Quadric]
    var isAlive: [Bool]
    var isPinned: [Bool]
    /// Counts the changes to each vertex, so a heap entry made before a change is known to be stale.
    var stamp: [UInt32]
    /// The live triangles that use each vertex.
    var incident: [[Int32]]
    var corners: [SIMD3<Int32>]
    var isTriangleAlive: [Bool]
    var liveTriangles: Int
    var heap = EdgeHeap()
    var collapses = 0

    /// - Throws: `MeshDecimator.Failure.nonManifold` when an edge has more than two faces.
    init(positions: [SIMD3<Float>], triangles: [UInt32]) throws {
        position = positions.map { SIMD3<Double>($0) }
        let count = positions.count
        corners = []
        corners.reserveCapacity(triangles.count / 3)
        for base in stride(from: 0, to: triangles.count - 2, by: 3) {
            let (a, b, c) = (triangles[base], triangles[base + 1], triangles[base + 2])
            // A triangle with a repeated or missing vertex is no face.
            guard a != b, b != c, a != c, Int(max(a, b, c)) < count else { continue }
            corners.append(SIMD3(Int32(a), Int32(b), Int32(c)))
        }
        quadric = [Quadric](repeating: Quadric(), count: count)
        isAlive = [Bool](repeating: true, count: count)
        isPinned = [Bool](repeating: false, count: count)
        stamp = [UInt32](repeating: 0, count: count)
        incident = [[Int32]](repeating: [], count: count)
        isTriangleAlive = [Bool](repeating: true, count: corners.count)
        liveTriangles = corners.count
        for (index, triangle) in corners.enumerated() {
            let (a, b, c) = (Int(triangle.x), Int(triangle.y), Int(triangle.z))
            let plane = Quadric(triangle: position[a], position[b], position[c])
            quadric[a] += plane
            quadric[b] += plane
            quadric[c] += plane
            incident[a].append(Int32(index))
            incident[b].append(Int32(index))
            incident[c].append(Int32(index))
        }
        let edges = try pinOpenEdges()
        heap.reserve(edges.count)
        for (u, v) in edges { if let entry = candidate(u, v, limit: .infinity) { heap.push(entry) } }
    }

    /// Pins the ends of every edge with a single face and returns every distinct edge as (low, high).
    private mutating func pinOpenEdges() throws -> [(Int, Int)] {
        var keys: [UInt64] = []
        keys.reserveCapacity(corners.count * 3)
        for triangle in corners {
            for side in 0..<3 {
                let (a, b) = (UInt64(triangle[side]), UInt64(triangle[(side + 1) % 3]))
                keys.append(min(a, b) << 32 | max(a, b))
            }
        }
        keys.sort()
        var edges: [(Int, Int)] = []
        var overfull = 0
        var start = 0
        while start < keys.count {
            var end = start + 1
            while end < keys.count, keys[end] == keys[start] { end += 1 }
            let (low, high) = (Int(keys[start] >> 32), Int(keys[start] & 0xFFFF_FFFF))
            edges.append((low, high))
            if end - start == 1 {
                isPinned[low] = true
                isPinned[high] = true
            } else if end - start > 2 {
                overfull += 1
            }
            start = end
        }
        if overfull > 0 { throw MeshDecimator.Failure.nonManifold(edges: overfull) }
        return edges
    }

    /// Where collapsing the edge (u, v) puts the new vertex, and what that costs (the quadric error there), or `nil` when both ends
    /// are pinned. A pinned end stays where it is; otherwise the best of both ends, the middle and the quadric's own optimum when
    /// that is near the edge.
    func target(_ u: Int, _ v: Int) -> (point: SIMD3<Double>, cost: Double)? {
        if isPinned[u] && isPinned[v] { return nil }
        let sum = quadric[u] + quadric[v]
        let (pu, pv) = (position[u], position[v])
        if isPinned[u] { return (pu, sum.error(at: pu)) }
        if isPinned[v] { return (pv, sum.error(at: pv)) }
        var best = (point: pu, cost: sum.error(at: pu))
        func consider(_ point: SIMD3<Double>) {
            let cost = sum.error(at: point)
            if cost < best.cost { best = (point, cost) }
        }
        let middle = (pu + pv) / 2
        consider(pv)
        consider(middle)
        if let optimum = sum.optimum(), (optimum - middle).length <= 2 * (pu - pv).length { consider(optimum) }
        return best
    }

    /// A heap entry for collapsing (u, v), or `nil` when it can't be done within `limit` (the squared tolerance).
    func candidate(_ u: Int, _ v: Int, limit: Double) -> EdgeHeap.Entry? {
        guard let chosen = target(u, v), chosen.cost <= limit else { return nil }
        return EdgeHeap.Entry(cost: chosen.cost, u: Int32(u), v: Int32(v), stampU: stamp[u], stampV: stamp[v])
    }
}

extension Quadric {
    /// The quadric of the plane of a triangle; zero for a triangle with no area.
    init(triangle a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
        let normal = (b - a).cross(c - a)
        let length = normal.length
        guard length > 1e-300 else {
            self.init()
            return
        }
        self.init(normal: normal / length, through: a)
    }
}
