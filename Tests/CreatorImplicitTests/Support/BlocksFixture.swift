import CreatorGeometry
import CreatorImplicit

/// Distance blocks filled from a function at every sample, for tests (the real baker is `DistanceBaker`).
enum BlocksFixture {
    /// `blocks` blocks on each axis, with sample (0, 0, 0) at `origin`.
    static func make(origin: Vector3, spacing: Double, blocks: Int, band: Double = 1000,
                     _ distance: (Vector3) -> Double) -> DistanceBlocks {
        let size = DistanceBlocks.blockSize
        let samples = blocks * size
        var pool: [Float] = []
        pool.reserveCapacity(blocks * blocks * blocks * size * size * size)
        for bz in 0..<blocks {
            for by in 0..<blocks {
                for bx in 0..<blocks {
                    for z in 0..<size {
                        for y in 0..<size {
                            for x in 0..<size {
                                let index = Vector3(Double(bx * size + x), Double(by * size + y), Double(bz * size + z))
                                pool.append(Float(distance(origin + index * spacing)))
                            }
                        }
                    }
                }
            }
        }
        _ = samples
        let count = blocks * blocks * blocks
        return DistanceBlocks(origin: origin, spacing: spacing, blockCounts: [blocks, blocks, blocks],
                              table: (0..<count).map(Int32.init), pool: pool, coarse: [Float](repeating: 0, count: count), band: band)
    }
}
