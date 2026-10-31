import CreatorGeometry
import CreatorKernel
import Foundation

/// The cross-section of a triangle mesh by a plane (section analysis part B). The mesh is welded by exact position, each vertex
/// takes the side of the plane it is on (a vertex exactly on the plane counts as the positive side, so no segment is degenerate),
/// each triangle with vertices on both sides gives one segment between two crossing edges, and the segments chain into loops.
/// A closed loop bounds material: loops are nested by even-odd containment, an even depth being an outer loop and an odd one a
/// hole of the loop directly around it, and each outer loop with its holes is triangulated. A chain that does not close (an open
/// mesh) is reported as an open outline and never filled. Collinear points on a loop (the diagonals of a flat face) are dropped.
public enum MeshSlicer {
    /// How many vertices or triangles pass between two looks at `Task.isCancelled`.
    static let cancellationStride = 4096

    /// A mesh welded by exact position, with its triangles remapped to the welded vertices and the degenerate ones (two corners
    /// welded together) removed. Built once per mesh by `prepare` and sliced at as many planes as needed.
    public final class Prepared: Sendable {
        let vertices: [Vector3]
        /// Three welded vertex numbers per triangle.
        let triangles: [UInt32]
        /// True when the surrounding task was cancelled part-way: the contents are incomplete and must not be kept.
        public let wasCancelled: Bool

        init(vertices: [Vector3], triangles: [UInt32], wasCancelled: Bool) {
            self.vertices = vertices
            self.triangles = triangles
            self.wasCancelled = wasCancelled
        }
    }

    /// The weld of a mesh (`positions`, three `triangles` indices each). Run in a cancelled task it returns early with
    /// `wasCancelled` set.
    public static func prepare(positions: [Vector3], triangles: [UInt32]) -> Prepared {
        var welded: [Crossings.Key: UInt32] = [:]
        welded.reserveCapacity(positions.count)
        var vertices: [Vector3] = []
        vertices.reserveCapacity(positions.count)
        var remap: [UInt32] = []
        remap.reserveCapacity(positions.count)
        for (number, position) in positions.enumerated() {
            if number % cancellationStride == 0, Task.isCancelled {
                return Prepared(vertices: [], triangles: [], wasCancelled: true)
            }
            let key = Crossings.Key(position)
            if let found = welded[key] {
                remap.append(found)
            } else {
                let next = UInt32(vertices.count)
                welded[key] = next
                remap.append(next)
                vertices.append(position)
            }
        }
        var kept: [UInt32] = []
        kept.reserveCapacity(triangles.count)
        for first in stride(from: 0, to: triangles.count - 2, by: 3) {
            if (first / 3) % cancellationStride == 0, Task.isCancelled {
                return Prepared(vertices: [], triangles: [], wasCancelled: true)
            }
            let (a, b, c) = (remap[Int(triangles[first])], remap[Int(triangles[first + 1])], remap[Int(triangles[first + 2])])
            guard a != b, b != c, a != c else { continue }
            kept.append(a)
            kept.append(b)
            kept.append(c)
        }
        return Prepared(vertices: vertices, triangles: kept, wasCancelled: false)
    }

    /// The section of the mesh (`positions`, three `triangles` indices each) by `plane`. Run in a cancelled task it returns early with
    /// an empty section; the caller checks for cancellation and discards it.
    public static func slice(positions: [Vector3], triangles: [UInt32], plane: Plane) -> PlaneSection {
        slice(prepare(positions: positions, triangles: triangles), plane: plane)
    }

    /// The section of a prepared mesh by `plane`, with the cancellation behaviour of `slice(positions:triangles:plane:)`.
    public static func slice(_ prepared: Prepared, plane: Plane) -> PlaneSection {
        guard !prepared.wasCancelled else { return PlaneSection() }
        let crossings = Crossings(prepared, plane: plane)
        guard !crossings.wasCancelled, !crossings.segments.isEmpty else { return PlaneSection() }
        var closed: [[Vector3]] = []
        var open: [[Vector3]] = []
        for chain in crossings.chains() {
            if Task.isCancelled { return PlaneSection() }
            let points = chain.nodes.map { crossings.points[$0] }
            if chain.isClosed {
                let kept = simplified(points, closed: true)
                if kept.count >= 3 { closed.append(kept) }
            } else {
                let kept = simplified(points, closed: false)
                if kept.count >= 2 { open.append(kept) }
            }
        }
        return PlaneSection(regions: regions(of: closed, on: plane), openOutlines: open)
    }

    // MARK: - Regions

    private struct Loop {
        var points: [Vector3]
        var flat: [Vector2]
        var area: Double
        var low: Vector2
        var high: Vector2
    }

    private static func regions(of loops: [[Vector3]], on plane: Plane) -> [SectionRegion] {
        let yAxis = plane.yAxis
        let all: [Loop] = loops.map { points in
            let flat = points.map { Vector2(($0 - plane.origin).dot(plane.xAxis), ($0 - plane.origin).dot(yAxis)) }
            let xs = flat.map(\.x), ys = flat.map(\.y)
            let area = abs(PolygonTriangulator.doubleArea(flat)) / 2
            return Loop(points: points, flat: flat, area: area, low: Vector2(xs.min() ?? 0, ys.min() ?? 0),
                        high: Vector2(xs.max() ?? 0, ys.max() ?? 0))
        }
        // The loops around each loop: bounding box first, then even-odd containment of its first point.
        let around: [[Int]] = all.indices.map { index in
            let inner = all[index]
            return all.indices.filter { other in
                guard other != index else { return false }
                let outer = all[other]
                guard outer.area > inner.area, outer.low.x <= inner.low.x, outer.low.y <= inner.low.y,
                      outer.high.x >= inner.high.x, outer.high.y >= inner.high.y else { return false }
                return PolygonTriangulator.contains(outer.flat, inner.flat[0])
            }
        }
        var holes: [Int: [Int]] = [:]
        for index in all.indices where around[index].count % 2 == 1 {
            let parent = around[index].filter { around[$0].count == around[index].count - 1 }.min { all[$0].area < all[$1].area }
            if let parent { holes[parent, default: []].append(index) }
        }
        return all.indices.filter { around[$0].count % 2 == 0 }.map { index in
            let members = [index] + (holes[index] ?? [])
            let flats = PolygonTriangulator.triangles(outer: all[index].flat, holes: (holes[index] ?? []).map { all[$0].flat })
            return SectionRegion(
                positions: flats.map { plane.point($0) }, triangles: (0..<UInt32(flats.count)).map { $0 },
                boundary: members.map { SectionPiece(curve: nil, polyline: all[$0].points + [all[$0].points[0]], sourceFace: nil) })
        }
    }

    // MARK: - Simplifying

    /// `points` without a point that repeats a neighbour or lies on the straight line between its neighbours, in one pass over a
    /// stack (a point is dropped when it is flat against the kept point before it and the point after it). A closed loop is then
    /// checked once more across its seam; it keeps at least three points and an open chain keeps both ends and at least two.
    private static func simplified(_ points: [Vector3], closed: Bool) -> [Vector3] {
        func isFlat(_ before: Vector3, _ here: Vector3, _ after: Vector3) -> Bool {
            let (back, forward) = (here - before, after - here)
            let (backLength, forwardLength) = (back.length, forward.length)
            return backLength <= 1e-12 || forwardLength <= 1e-12
                || (back.cross(forward).length <= 1e-9 * backLength * forwardLength && back.dot(forward) > 0)
        }
        let minimum = closed ? 3 : 2
        var kept: [Vector3] = []
        kept.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            while kept.count >= 2, points.count - index + kept.count > minimum, isFlat(kept[kept.count - 2], kept[kept.count - 1], point) {
                kept.removeLast()
            }
            kept.append(point)
        }
        guard closed else { return kept }
        var head = 0
        var changed = true
        while changed, kept.count - head > minimum {
            changed = false
            if isFlat(kept[kept.count - 2], kept[kept.count - 1], kept[head]) {
                kept.removeLast()
                changed = true
            } else if kept.count - head > minimum, isFlat(kept[kept.count - 1], kept[head], kept[head + 1]) {
                head += 1
                changed = true
            }
        }
        return Array(kept[head...])
    }
}

/// The crossing points of a plane with a welded mesh, and the segments between them.
private struct Crossings {
    /// The crossing point of each node (a welded edge that crosses the plane).
    var points: [Vector3] = []
    /// Two node numbers per segment, one segment per crossing triangle.
    var segments: [(Int, Int)] = []
    /// True when the surrounding task was cancelled part-way, so the rest is not computed.
    private(set) var wasCancelled = false
    /// Two segment slots per node (-1 when empty): a node of a manifold section has two segments.
    private var slots: [Int32] = []
    /// The segments a node has beyond its two slots (a non-manifold crossing), by node.
    private var overflow: [Int: [Int32]] = [:]

    struct Key: Hashable {
        var x: UInt64
        var y: UInt64
        var z: UInt64
        init(_ v: Vector3) {
            // Adding zero turns -0 into +0, so equal positions have equal bits.
            (x, y, z) = ((v.x + 0).bitPattern, (v.y + 0).bitPattern, (v.z + 0).bitPattern)
        }
    }

    init(_ mesh: MeshSlicer.Prepared, plane: Plane) {
        let vertices = mesh.vertices
        let distance = vertices.map { ($0 - plane.origin).dot(plane.normal) }
        var nodes: [UInt64: Int] = [:]
        func node(_ a: UInt32, _ b: UInt32) -> Int {
            let (low, high) = a < b ? (a, b) : (b, a)
            let key = UInt64(low) << 32 | UInt64(high)
            if let found = nodes[key] { return found }
            let (lowIndex, highIndex) = (Int(low), Int(high))
            let t = distance[lowIndex] / (distance[lowIndex] - distance[highIndex])
            points.append(vertices[lowIndex] + (vertices[highIndex] - vertices[lowIndex]) * t)
            slots.append(-1)
            slots.append(-1)
            nodes[key] = points.count - 1
            return points.count - 1
        }
        let triangles = mesh.triangles
        for first in stride(from: 0, to: triangles.count - 2, by: 3) {
            if (first / 3) % MeshSlicer.cancellationStride == 0, Task.isCancelled {
                wasCancelled = true
                return
            }
            let (c0, c1, c2) = (triangles[first], triangles[first + 1], triangles[first + 2])
            let (a0, a1, a2) = (distance[Int(c0)] >= 0, distance[Int(c1)] >= 0, distance[Int(c2)] >= 0)
            guard a0 != a1 || a1 != a2 else { continue }
            // The lone corner on its own side, and the two others: the crossing edges run from it.
            let (p, q, r): (UInt32, UInt32, UInt32)
            if a0 == a1 {
                (p, q, r) = (c2, c0, c1)
            } else if a0 == a2 {
                (p, q, r) = (c1, c2, c0)
            } else {
                (p, q, r) = (c0, c1, c2)
            }
            let (a, b) = (node(p, q), node(p, r))
            attach(segments.count, to: a)
            attach(segments.count, to: b)
            segments.append((a, b))
        }
    }

    private mutating func attach(_ segment: Int, to node: Int) {
        if slots[2 * node] < 0 {
            slots[2 * node] = Int32(segment)
        } else if slots[2 * node + 1] < 0 {
            slots[2 * node + 1] = Int32(segment)
        } else {
            overflow[node, default: []].append(Int32(segment))
        }
    }

    /// The first segment at `node` that is not `used`.
    private func firstUnused(at node: Int, _ used: [Bool]) -> Int? {
        for slot in 2 * node..<2 * node + 2 where slots[slot] >= 0 && !used[Int(slots[slot])] {
            return Int(slots[slot])
        }
        if let more = overflow[node] {
            for segment in more where !used[Int(segment)] { return Int(segment) }
        }
        return nil
    }

    private func unusedCount(at node: Int, _ used: [Bool]) -> Int {
        var count = 0
        for slot in 2 * node..<2 * node + 2 where slots[slot] >= 0 && !used[Int(slots[slot])] { count += 1 }
        if let more = overflow[node] {
            for segment in more where !used[Int(segment)] { count += 1 }
        }
        return count
    }

    struct Chain {
        var nodes: [Int]
        var isClosed: Bool
    }

    /// The segments chained: open chains from their loose ends first, then what is left as loops.
    func chains() -> [Chain] {
        var used = [Bool](repeating: false, count: segments.count)
        var result: [Chain] = []
        func walk(from start: Int) -> [Int] {
            var nodes = [start]
            var current = start
            while let next = firstUnused(at: current, used) {
                used[next] = true
                let (a, b) = segments[next]
                current = a == current ? b : a
                nodes.append(current)
            }
            return nodes
        }
        for start in points.indices where unusedCount(at: start, used) % 2 == 1 {
            result.append(Chain(nodes: walk(from: start), isClosed: false))
        }
        for start in points.indices where firstUnused(at: start, used) != nil {
            var nodes = walk(from: start)
            let closes = nodes.count > 1 && nodes.last == start
            if closes { nodes.removeLast() }
            result.append(Chain(nodes: nodes, isClosed: closes))
        }
        return result
    }
}
