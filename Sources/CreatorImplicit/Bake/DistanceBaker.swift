import CreatorGeometry
import Foundation

/// Bakes a signed distance function onto `DistanceBlocks` (implicit spec §4.4).
public enum DistanceBaker {
    /// What a bake made.
    public struct Result: Sendable {
        public var blocks: DistanceBlocks
        /// The sample spacing used, which is more than asked for when the part was too big for the block budget.
        public var spacing: Double
        public var seconds: Double
    }

    /// The most blocks the grid may have, stored or not, and the most it may store. A part that needs more is baked coarser.
    public static let maximumGridBlocks = 4_000_000
    public static let maximumStoredBlocks = 40_000

    /// The sample spacing a tolerance asks for. Trilinear interpolation of a distance field is off by about `spacing² ÷ (8 R)` where
    /// the surface curves with radius R; taking R = 2 mm (a fillet that tight is rare) gives `√(16 · tolerance)`: 0.4 mm for the
    /// default 0.01 mm.
    public static func spacing(forTolerance tolerance: Double) -> Double {
        (16 * tolerance).squareRoot()
    }

    /// Bakes `distance` over `bounds` (the surface's box).
    /// - Parameters:
    ///   - spacing: the sample spacing; raised in steps of 26% until the grid and the stored blocks fit the limits.
    ///   - gridLimit: the most blocks the grid may have, stored or not; `storedLimit`, the most it may store.
    ///   - bandBlocks: how far from the surface blocks are stored, in blocks (implicit spec §4.4 says 4; the default 1 stores the blocks
    ///     the surface passes through and their neighbours' worth of margin).
    ///   - distance: the exact signed distance, called from several tasks at once.
    public static func bake(bounds: BoundingBox, spacing requested: Double, bandBlocks: Double = 1,
                            gridLimit: Int = maximumGridBlocks, storedLimit: Int = maximumStoredBlocks,
                            distance: @escaping @Sendable (Vector3) -> Double) async throws -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        let size = DistanceBlocks.blockSize
        var spacing = requested
        while true {
            try Task.checkCancellation()
            let length = Double(size) * spacing
            let band = bandBlocks * length
            let origin = bounds.min - Vector3(band + length, band + length, band + length)
            let span = bounds.max + Vector3(band + length, band + length, band + length) - origin
            let counts = [span.x, span.y, span.z].map { max(1, Int(($0 / length).rounded(.up))) }
            let total = counts.reduce(1, *)
            if total > gridLimit { spacing *= 1.26; continue }
            // First, one probe at each block's centre decides which blocks are stored.
            let reach = length * 3.0.squareRoot() / 2
            var table = [Int32](repeating: -1, count: total)
            var coarse = [Float](repeating: 0, count: total)
            var stored: [Int] = []
            for block in 0..<total {
                if block % 4096 == 0 { try Task.checkCancellation() }
                let centre = origin + Vector3(Double(block % counts[0]) + 0.5, Double((block / counts[0]) % counts[1]) + 0.5,
                                              Double(block / (counts[0] * counts[1])) + 0.5) * length
                let value = distance(centre)
                let lower = abs(value) - reach
                if lower < band {
                    table[block] = Int32(stored.count)
                    stored.append(block)
                } else {
                    coarse[block] = Float(value < 0 ? -lower : lower)
                }
            }
            if stored.count > storedLimit { spacing *= 1.26; continue }
            let pool = try await samples(of: stored, counts: counts, origin: origin, spacing: spacing, distance: distance)
            let blocks = DistanceBlocks(origin: origin, spacing: spacing, blockCounts: counts, table: table, pool: pool, coarse: coarse,
                                        band: band)
            return Result(blocks: blocks, spacing: spacing, seconds: start.duration(to: clock.now) / .seconds(1))
        }
    }

    /// The 512 samples of each stored block, in `stored` order. Several tasks each take a run of blocks.
    private static func samples(of stored: [Int], counts: [Int], origin: Vector3, spacing: Double,
                                distance: @escaping @Sendable (Vector3) -> Double) async throws -> [Float] {
        let size = DistanceBlocks.blockSize
        let perBlock = size * size * size
        let tasks = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, stored.count))
        let run = (stored.count + tasks - 1) / max(tasks, 1)
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for first in stride(from: 0, to: stored.count, by: max(run, 1)) {
                let blocks = Array(stored[first..<min(first + run, stored.count)])
                group.addTask {
                    var values: [Float] = []
                    values.reserveCapacity(blocks.count * perBlock)
                    for block in blocks {
                        try Task.checkCancellation()
                        let (bx, by, bz) = (block % counts[0], (block / counts[0]) % counts[1], block / (counts[0] * counts[1]))
                        for z in 0..<size {
                            for y in 0..<size {
                                for x in 0..<size {
                                    let index = Vector3(Double(bx * size + x), Double(by * size + y), Double(bz * size + z))
                                    values.append(Float(distance(origin + index * spacing)))
                                }
                            }
                        }
                    }
                    return (first, values)
                }
            }
            var runs: [(Int, [Float])] = []
            for try await result in group { runs.append(result) }
            return runs.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }
}
