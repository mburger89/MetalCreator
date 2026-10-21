import CreatorGeometry

/// The grid a face chart is sampled on (implicit spec §3.5, Face mapping): blocks of 8 × 8 × 8 samples like `DistanceBlocks`, laid over
/// a box, every sample stored. Samples are numbered x fastest, then y, then z.
public struct FaceChartGrid: Hashable, Sendable {
    /// The most samples a chart has: the kernel projects every one onto the face, which costs about 40 µs of a thread each.
    public static let maximumSamples = 125_000

    public let origin: Vector3
    public let spacing: Double
    /// Blocks along x, y and z; the samples are eight times as many.
    public let blockCounts: [Int]

    /// - Parameters:
    ///   - box: what the grid must cover.
    ///   - spacing: the sample spacing wanted, in millimetres; raised in steps of 26% until the grid has at most `maximumSamples`.
    public init(covering box: BoundingBox, spacing wanted: Double) {
        var spacing = max(wanted, 1e-3)
        // The last sample of 8 blocks is at 8 × blocks − 1 spacings from the first, and has to reach the box's far side.
        func counts(_ spacing: Double) -> [Int] {
            [box.size.x, box.size.y, box.size.z].map { max(1, Int((($0 / spacing + 1) / Double(DistanceBlocks.blockSize)).rounded(.up))) }
        }
        while counts(spacing).reduce(1, *) * DistanceBlocks.blockSize * DistanceBlocks.blockSize * DistanceBlocks.blockSize
            > Self.maximumSamples {
            spacing *= 1.26
        }
        origin = box.min
        self.spacing = spacing
        blockCounts = counts(spacing)
    }

    /// Samples along x, y and z.
    public var counts: [Int] { blockCounts.map { $0 * DistanceBlocks.blockSize } }

    public var sampleCount: Int { counts.reduce(1, *) }

    /// The box the samples span.
    public var bounds: BoundingBox {
        let last = counts.map { Double($0 - 1) * spacing }
        return BoundingBox(min: origin, max: origin + Vector3(last[0], last[1], last[2]))
    }

    /// The position of every sample, in numbering order.
    public var points: [Vector3] {
        let (nx, ny, nz) = (counts[0], counts[1], counts[2])
        var points: [Vector3] = []
        points.reserveCapacity(nx * ny * nz)
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    points.append(origin + Vector3(Double(i), Double(j), Double(k)) * spacing)
                }
            }
        }
        return points
    }

    /// `values` (one per sample, in numbering order) as blocks with every one stored. `lipschitz` is what the caller knows of how fast
    /// they change per millimetre.
    public func blocks(_ values: [Float], lipschitz: Double) -> DistanceBlocks {
        let size = DistanceBlocks.blockSize
        let (nx, ny) = (counts[0], counts[1])
        var pool: [Float] = []
        pool.reserveCapacity(values.count)
        for bz in 0..<blockCounts[2] {
            for by in 0..<blockCounts[1] {
                for bx in 0..<blockCounts[0] {
                    for z in 0..<size {
                        for y in 0..<size {
                            let row = ((bz * size + z) * ny + by * size + y) * nx + bx * size
                            pool += values[row..<row + size]
                        }
                    }
                }
            }
        }
        let total = blockCounts.reduce(1, *)
        return DistanceBlocks(origin: origin, spacing: spacing, blockCounts: blockCounts, table: (0..<total).map(Int32.init), pool: pool,
                              coarse: [Float](repeating: 0, count: total), band: bounds.size.length, lipschitz: lipschitz)
    }
}
