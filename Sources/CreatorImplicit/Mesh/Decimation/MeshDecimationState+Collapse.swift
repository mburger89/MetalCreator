extension MeshDecimationState {
    private func uses(_ triangle: SIMD3<Int32>, _ vertex: Int32) -> Bool {
        triangle.x == vertex || triangle.y == vertex || triangle.z == vertex
    }

    /// The vertices that share a live triangle with `vertex`, other than `vertex` and `excluding`.
    private func neighbours(of vertex: Int, excluding: Int) -> [Int32] {
        var found: [Int32] = []
        for index in incident[vertex] where isTriangleAlive[Int(index)] {
            let triangle = corners[Int(index)]
            for corner in [triangle.x, triangle.y, triangle.z] where Int(corner) != vertex && Int(corner) != excluding {
                if !found.contains(corner) { found.append(corner) }
            }
        }
        return found
    }

    /// The link condition: the two ends of the edge share as many neighbours as the edge has faces. Otherwise collapsing it would pinch
    /// the surface into a non-manifold vertex or edge.
    func keepsTheSurfaceManifold(_ u: Int, _ v: Int) -> Bool {
        let faces = incident[u].filter { isTriangleAlive[Int($0)] && uses(corners[Int($0)], Int32(v)) }.count
        let uSide = neighbours(of: u, excluding: v)
        let shared = neighbours(of: v, excluding: u).filter { uSide.contains($0) }.count
        return shared == faces && faces > 0
    }

    /// Whether moving `moving` to `point` leaves every triangle around it, except those on the edge to `other`, facing roughly the way it
    /// did and with some area.
    func keepsFacing(moving: Int, other: Int, to point: SIMD3<Double>) -> Bool {
        let tag = Int32(moving)
        for index in incident[moving] where isTriangleAlive[Int(index)] {
            let triangle = corners[Int(index)]
            if uses(triangle, Int32(other)) { continue }
            let (a, b, c) = (position[Int(triangle.x)], position[Int(triangle.y)], position[Int(triangle.z)])
            let (na, nb, nc) = (triangle.x == tag ? point : a, triangle.y == tag ? point : b, triangle.z == tag ? point : c)
            let (before, after) = ((b - a).cross(c - a), (nb - na).cross(nc - na))
            let (lengthBefore, lengthAfter) = (before.length, after.length)
            if lengthBefore == 0 { continue }
            if lengthAfter <= 1e-9 * lengthBefore || before.dot(after) < 0.1 * lengthBefore * lengthAfter { return false }
        }
        return true
    }

    /// Collapses the edge: `drop` joins `keep`, which moves to `point`. The triangles on the edge go; the others that used `drop` use
    /// `keep`.
    mutating func collapse(keep: Int, drop: Int, to point: SIMD3<Double>) {
        let (kept, dropped) = (Int32(keep), Int32(drop))
        var around = incident[keep].filter { isTriangleAlive[Int($0)] && !uses(corners[Int($0)], dropped) }
        for index in incident[keep] where isTriangleAlive[Int(index)] && uses(corners[Int(index)], dropped) {
            isTriangleAlive[Int(index)] = false
            liveTriangles -= 1
            let triangle = corners[Int(index)]
            for corner in [triangle.x, triangle.y, triangle.z] where corner != kept && corner != dropped {
                incident[Int(corner)].removeAll { $0 == index }
            }
        }
        for index in incident[drop] where isTriangleAlive[Int(index)] {
            var triangle = corners[Int(index)]
            if triangle.x == dropped { triangle.x = kept } else if triangle.y == dropped { triangle.y = kept } else { triangle.z = kept }
            corners[Int(index)] = triangle
            around.append(index)
        }
        incident[keep] = around
        incident[drop] = []
        position[keep] = point
        quadric[keep] += quadric[drop]
        isPinned[keep] = isPinned[keep] || isPinned[drop]
        isAlive[drop] = false
        stamp[keep] &+= 1
        collapses += 1
    }

    /// Pushes a fresh candidate for every edge at `vertex`, after it changed.
    mutating func requeue(around vertex: Int, limit: Double) {
        for other in neighbours(of: vertex, excluding: vertex) {
            if let entry = candidate(vertex, Int(other), limit: limit) { heap.push(entry) }
        }
    }

    /// Collapses the cheapest legal edges until none is left within `tolerance`, or the mesh is down to a tetrahedron.
    mutating func run(tolerance: Double) throws {
        let limit = tolerance * tolerance
        var steps = 0
        while liveTriangles > 4, let entry = heap.pop() {
            steps += 1
            if steps & 0xFFF == 0 { try Task.checkCancellation() }
            let (u, v) = (Int(entry.u), Int(entry.v))
            guard isAlive[u], isAlive[v], stamp[u] == entry.stampU, stamp[v] == entry.stampV,
                  let chosen = target(u, v), chosen.cost <= limit else { continue }
            guard keepsTheSurfaceManifold(u, v), keepsFacing(moving: u, other: v, to: chosen.point),
                  keepsFacing(moving: v, other: u, to: chosen.point) else { continue }
            let (keep, drop) = isPinned[v] ? (v, u) : (u, v)
            collapse(keep: keep, drop: drop, to: chosen.point)
            requeue(around: keep, limit: limit)
        }
    }

    /// The surviving vertices and triangles, renumbered in order of first use.
    func output() -> MeshDecimator.Output {
        var remap = [Int32](repeating: -1, count: position.count)
        var positions: [SIMD3<Float>] = []
        var origin: [Int32] = []
        var triangles: [UInt32] = []
        triangles.reserveCapacity(liveTriangles * 3)
        for (index, triangle) in corners.enumerated() where isTriangleAlive[index] {
            for vertex in [Int(triangle.x), Int(triangle.y), Int(triangle.z)] {
                if remap[vertex] < 0 {
                    remap[vertex] = Int32(positions.count)
                    positions.append(SIMD3<Float>(position[vertex]))
                    origin.append(Int32(vertex))
                }
                triangles.append(UInt32(remap[vertex]))
            }
        }
        return MeshDecimator.Output(positions: positions, triangles: triangles, origin: origin, collapses: collapses)
    }
}
