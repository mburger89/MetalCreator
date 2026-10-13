import CreatorGeometry

/// A big mesh's coarse sampling (fields spec §6 and D14): over `vertexLimit` vertices a deterministic subset of exactly that many
/// is sampled, evenly spaced in mesh order, and every other vertex takes the value of the nearest sampled vertex (ties to the
/// lower one), found with a grid, so the legend can say "Preview sampled coarsely" and the tint stays interactive.
enum CoarseSampling {
    /// The spec's number (D14).
    static let vertexLimit = 200_000

    /// The vertices to sample: all of them when there are at most `limit`, else `limit` indices `i × count / limit`.
    static func sampledIndices(count: Int, limit: Int = vertexLimit) -> [Int] {
        guard count > limit, limit > 0 else { return Array(0..<max(count, 0)) }
        return (0..<limit).map { $0 * count / limit }
    }

    /// One value per vertex: each sampled vertex keeps its own (`values[n]` for `positions[indices[n]]`), every other takes the
    /// nearest sampled vertex's. Checks for cancellation as it goes.
    static func expand(positions: [Vector3], sampled indices: [Int], values: [Double]) throws -> [Float] {
        precondition(indices.count == values.count, "one value per sampled vertex")
        guard !indices.isEmpty else { return [Float](repeating: .nan, count: positions.count) }
        if indices.count == positions.count { return values.map { Float($0) } }
        // The grid covers every vertex, not only the sampled ones: a vertex outside the sampled points' box still finds its nearest.
        guard let box = BoundingBox(points: positions) else { return [] }
        let grid = Grid(points: indices.map { positions[$0] }, box: box)
        var result = [Float](repeating: .nan, count: positions.count)
        for (slot, index) in indices.enumerated() { result[index] = Float(values[slot]) }
        let isSampled = Set(indices)
        for (vertex, position) in positions.enumerated() where !isSampled.contains(vertex) {
            if vertex % 4_096 == 0 { try Task.checkCancellation() }
            if let slot = grid.nearest(to: position) { result[vertex] = Float(values[slot]) }
        }
        return result
    }

    private struct Cell: Hashable {
        var x: Int32
        var y: Int32
        var z: Int32
    }

    /// The sampled points in a grid of cubes about one point to a cube on average (a surface: about the square root of their
    /// number across the widest side), for nearest-point searches.
    private struct Grid {
        let points: [Vector3]
        let origin: Vector3
        let width: Double
        /// The ring of cubes beyond which nothing can be.
        let widest: Int32
        private var cells: [Cell: [Int]] = [:]

        init(points: [Vector3], box: BoundingBox) {
            self.points = points
            origin = box.min
            let size = box.size
            let longest = max(size.x, size.y, size.z)
            width = max(longest / max(Double(points.count).squareRoot(), 1), 1e-9)
            widest = Int32(clamping: Int((longest / width).rounded(.up)) + 1)
            for (slot, point) in points.enumerated() { cells[cell(of: point), default: []].append(slot) }
        }

        private func cell(of point: Vector3) -> Cell {
            func index(_ value: Double, from start: Double) -> Int32 { Int32(clamping: Int(((value - start) / width).rounded(.down))) }
            return Cell(x: index(point.x, from: origin.x), y: index(point.y, from: origin.y), z: index(point.z, from: origin.z))
        }

        /// The slot of the sampled point nearest `position`, the lowest slot among equals; `nil` with no points.
        func nearest(to position: Vector3) -> Int? {
            let home = cell(of: position)
            var best: (slot: Int, distance: Double)?
            for ring in 0...widest {
                for dx in -ring...ring {
                    for dy in -ring...ring {
                        for dz in -ring...ring where max(abs(dx), abs(dy), abs(dz)) == ring {
                            consider(Cell(x: home.x &+ dx, y: home.y &+ dy, z: home.z &+ dz), from: position, best: &best)
                        }
                    }
                }
                // Anything in a ring further out is at least `ring × width` away.
                if let found = best, found.distance <= Double(ring) * width { break }
            }
            return best?.slot
        }

        private func consider(_ cell: Cell, from position: Vector3, best: inout (slot: Int, distance: Double)?) {
            for slot in cells[cell] ?? [] {
                let distance = (points[slot] - position).length
                guard let current = best else {
                    best = (slot, distance)
                    continue
                }
                if distance < current.distance || (distance == current.distance && slot < current.slot) { best = (slot, distance) }
            }
        }
    }
}
