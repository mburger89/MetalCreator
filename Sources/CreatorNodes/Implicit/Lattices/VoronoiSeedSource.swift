import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// The built-in seeds of a Voronoi lattice (implicit spec §3.4): `count` points drawn uniformly through a box, each kept with the
/// probability the `density` field gives at it (clamped to 0 ... 1), until there are `count` of them.
///
/// Candidate `i` is drawn from `SeededRandom(seed:, purpose: .voronoi)` alone: its position from draws 4i to 4i + 2 and its
/// acceptance from draw 4i + 3. The seeds are the first `count` accepted candidates, in order, so a seed depends on the
/// `seed`, the density and the box, never on how the candidates were batched, and raising `count` keeps the seeds already there.
enum VoronoiSeedSource {
    static let maximumCount = 100_000
    /// The most candidates tried per seed wanted before the search gives up on a density that is almost 0.
    static let attemptsPerSeed = 100

    struct Result {
        var points: [Vector3]
        var warnings: [String]
    }

    /// The box the seeds fill for a region in `box`: the region grown by half the mean spacing, so the cells at its edge are real.
    static func area(for box: BoundingBox, count: Int) -> BoundingBox {
        let volume = max(box.size.x, 1e-3) * max(box.size.y, 1e-3) * max(box.size.z, 1e-3)
        return ImplicitSolid.grown(box, by: cbrt(volume / Double(max(count, 1))) / 2)
    }

    static func points(count: Int, density: Field, seed: Int, in box: BoundingBox, kernel: any Kernel,
                       cache: FieldDistanceCache) async throws -> Result {
        let area = area(for: box, count: count)
        let random = SeededRandom(seed: seed, purpose: .voronoi)
        var points: [Vector3] = []
        points.reserveCapacity(count)
        var next = 0
        let limit = attemptsPerSeed * count + 10_000
        while points.count < count && next < limit {
            try Task.checkCancellation()
            let wanted = count - points.count
            // Expect the acceptance seen so far to continue; the first batch is exactly what is wanted.
            let rate = next == 0 ? 1 : max(Double(points.count) / Double(next), 0.01)
            let size = min(max(Int((Double(wanted) * 1.5 / rate).rounded(.up)), 256), 200_000, limit - next)
            let candidates = (next..<next + size).map { index in
                area.min + Vector3(area.size.x * random.unit(at: 4 * index), area.size.y * random.unit(at: 4 * index + 1),
                                   area.size.z * random.unit(at: 4 * index + 2))
            }
            let values: [Double]
            if case .constant(let level) = density {
                values = [Double](repeating: level, count: size)
            } else {
                values = try await FieldSampler.sample(density, at: candidates, kernel: kernel, cache: cache)
            }
            for (offset, value) in values.enumerated() {
                let chance = value.isFinite ? min(max(value, 0), 1) : 0
                guard random.unit(at: 4 * (next + offset) + 3) < chance else { continue }
                points.append(candidates[offset])
                if points.count == count {
                    next += offset + 1
                    break
                }
            }
            if points.count < count { next += size }
        }
        var warnings: [String] = []
        if points.isEmpty {
            throw NodeError.invalidValue("The density is 0 everywhere in the region, so there are no seeds.")
        }
        if points.count < count {
            warnings.append("The density left room for only \(points.count.display) of the \(count.display) seeds.")
        }
        return Result(points: points, warnings: warnings)
    }
}
