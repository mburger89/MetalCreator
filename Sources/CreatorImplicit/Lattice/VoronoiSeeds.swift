import CreatorGeometry
import Foundation

/// The seeds of a Voronoi lattice on a uniform grid (implicit spec §3.4): cells of `radius` millimetres, so the 27 cells around a point
/// hold every seed within `radius` of it. Immutable; equal by identity, like `DistanceBlocks`, so a tree with thousands of seeds is
/// cheap to compare.
public final class VoronoiSeeds: Hashable, Sendable {
    /// The most grid cells there are; a larger grid is made with larger cells.
    public static let maximumCells = 1 << 21

    public let points: [Vector3]
    /// The grid's cell size, which is also how far from a point the evaluation looks for seeds.
    public let radius: Double
    /// The corner of cell (0, 0, 0).
    public let origin: Vector3
    /// Cells along x, y and z.
    public let counts: [Int]
    /// Where each cell's seeds start in `entries`: cell (x fastest, then y, then z) `c` owns `entries[starts[c] ..< starts[c + 1]]`.
    public let starts: [Int32]
    /// Seed numbers, grouped by cell.
    public let entries: [Int32]

    /// - Parameters:
    ///   - points: the seeds, at least one, all finite.
    ///   - radius: how far to look for seeds from a point, at least this; made larger if the grid would pass `maximumCells`.
    public init(points: [Vector3], radius requested: Double) {
        precondition(!points.isEmpty && requested > 0, "VoronoiSeeds needs a seed and a radius")
        let box = BoundingBox(points: points) ?? BoundingBox(min: .zero, max: .zero)
        var size = requested
        func counts(_ size: Double) -> [Int] {
            [box.size.x, box.size.y, box.size.z].map { Int(($0 / size).rounded(.down)) + 1 }
        }
        while counts(size).reduce(1, *) > Self.maximumCells { size *= 1.5 }
        self.points = points
        self.radius = size
        self.origin = box.min
        let found = counts(size)
        self.counts = found
        var cellOf: [Int] = []
        cellOf.reserveCapacity(points.count)
        var tally = [Int32](repeating: 0, count: found[0] * found[1] * found[2] + 1)
        for point in points {
            let (x, y, z) = (min(Int((point.x - box.min.x) / size), found[0] - 1), min(Int((point.y - box.min.y) / size), found[1] - 1),
                             min(Int((point.z - box.min.z) / size), found[2] - 1))
            let cell = (z * found[1] + y) * found[0] + x
            cellOf.append(cell)
            tally[cell + 1] += 1
        }
        for index in 1..<tally.count { tally[index] += tally[index - 1] }
        var fill = tally
        var sorted = [Int32](repeating: 0, count: points.count)
        for (seed, cell) in cellOf.enumerated() {
            sorted[Int(fill[cell])] = Int32(seed)
            fill[cell] += 1
        }
        self.starts = tally
        self.entries = sorted
    }

    /// The search radius for `count` seeds spread through `region`: twice the mean spacing, so a point with no seed within the
    /// radius is a hole that Poisson-like seeds essentially never leave.
    public static func searchRadius(count: Int, in region: BoundingBox) -> Double {
        let volume = max(region.size.x, 1e-3) * max(region.size.y, 1e-3) * max(region.size.z, 1e-3)
        return 2 * cbrt(volume / Double(max(count, 1)))
    }

    /// Calls `visit` with the number and position of every seed in the 27 grid cells around `p`: all seeds within `radius` of `p`, and
    /// some farther. A point outside the grid sees the cells that overlap its window, which may be none.
    public func forEachSeed(near p: Vector3, _ visit: (Int, Vector3) -> Void) {
        func cell(_ value: Double, _ count: Int) -> Int { Int(min(max((value / radius).rounded(.down), -2), Double(count + 1))) }
        let (cx, cy, cz) = (cell(p.x - origin.x, counts[0]), cell(p.y - origin.y, counts[1]), cell(p.z - origin.z, counts[2]))
        for z in cz - 1...cz + 1 where z >= 0 && z < counts[2] {
            for y in cy - 1...cy + 1 where y >= 0 && y < counts[1] {
                for x in cx - 1...cx + 1 where x >= 0 && x < counts[0] {
                    let index = (z * counts[1] + y) * counts[0] + x
                    for entry in Int(starts[index])..<Int(starts[index + 1]) {
                        let seed = Int(entries[entry])
                        visit(seed, points[seed])
                    }
                }
            }
        }
    }

    /// The distance to the nearest seed within the window of `p`, or `nil` when there is none (a seed farther than `radius` may be
    /// missed, which is the point: the lattice reads a hole there).
    public func nearestDistance(to p: Vector3) -> Double? {
        var nearest: Double?
        forEachSeed(near: p) { _, position in nearest = min(nearest ?? .infinity, (p - position).length) }
        return nearest
    }

    /// The fraction of a `steps`³ grid of points in `box` that is farther than three quarters of `radius` from every seed: where the
    /// lattice would be solid because the seeds don't reach (implicit spec §3.4's gaps). Poisson-like seeds from `searchRadius` leave
    /// essentially none.
    public func uncoveredFraction(in box: BoundingBox, steps: Int = 12) -> Double {
        var uncovered = 0
        for i in 0..<steps {
            for j in 0..<steps {
                for k in 0..<steps {
                    let fraction = Vector3(Double(i) + 0.5, Double(j) + 0.5, Double(k) + 0.5) * (1 / Double(steps))
                    let point = box.min + Vector3(box.size.x * fraction.x, box.size.y * fraction.y, box.size.z * fraction.z)
                    if (nearestDistance(to: point) ?? .infinity) > 0.75 * radius { uncovered += 1 }
                }
            }
        }
        return Double(uncovered) / Double(steps * steps * steps)
    }

    public var estimatedBytes: Int { points.count * 24 + starts.count * 4 + entries.count * 4 }

    public static func == (lhs: VoronoiSeeds, rhs: VoronoiSeeds) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
