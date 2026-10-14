import CreatorGeometry

/// A baked signed distance on a regular grid, stored sparsely (implicit spec §4.4): blocks of 8 × 8 × 8 `Float` samples, kept only
/// where the surface is within `band` of them, and for every other block one conservative value (a lower bound of the distance
/// there, with the sign of the side it is on). Within a block the value is trilinear between samples, so it is Lipschitz 1 to within
/// the interpolation error `spacing` is chosen to keep under the tolerance. Immutable; equal by identity.
public final class DistanceBlocks: Hashable, Sendable {
    /// Samples per block along each axis.
    public static let blockSize = 8

    /// World position of sample (0, 0, 0).
    public let origin: Vector3
    /// Distance between neighbouring samples, in millimetres.
    public let spacing: Double
    /// Blocks along x, y and z.
    public let blockCounts: [Int]
    /// For each block (x fastest, then y, then z): its place in `pool` (a block number), or -1 when it is not stored.
    public let table: [Int32]
    /// The stored blocks' samples, 512 per block (x fastest).
    public let pool: [Float]
    /// For each block: the signed lower bound used where it is not stored.
    public let coarse: [Float]
    /// Distances up to this size from the surface are stored exactly; beyond it the value is a bound.
    public let band: Double
    /// A bound on how fast the interpolated value changes: at least 1, and for a baked distance close to it. Inside one cell of
    /// samples the trilinear gradient is largest at a corner, so the bound is the largest vector of sample differences over `spacing`
    /// there, over the cells near the surface.
    public let lipschitz: Double

    public init(origin: Vector3, spacing: Double, blockCounts: [Int], table: [Int32], pool: [Float], coarse: [Float], band: Double) {
        precondition(blockCounts.count == 3 && table.count == blockCounts.reduce(1, *) && coarse.count == table.count,
                     "DistanceBlocks needs one table and one coarse entry per block")
        self.origin = origin
        self.spacing = spacing
        self.blockCounts = blockCounts
        self.table = table
        self.pool = pool
        self.coarse = coarse
        self.band = band
        self.lipschitz = Self.interpolationSlope(blockCounts: blockCounts, table: table, pool: pool, coarse: coarse, spacing: spacing,
                                              band: band)
    }

    /// The bound `lipschitz` describes. The squared gradient of a trilinear cell is convex in position, so its largest value is at a
    /// corner, where the gradient is the three sample differences along the edges that meet there. Only cells within half the band of
    /// the surface count: deeper in, the true distance has ridges (the medial axis) that no pruning decision depends on.
    private static func interpolationSlope(blockCounts: [Int], table: [Int32], pool: [Float], coarse: [Float], spacing: Double,
                                           band: Double) -> Double {
        let size = blockSize
        let counts = blockCounts.map { $0 * size }
        func sample(_ i: Int, _ j: Int, _ k: Int) -> Float {
            let block = ((k / size) * blockCounts[1] + j / size) * blockCounts[0] + i / size
            let slot = Int(table[block])
            guard slot >= 0 else { return coarse[block] }
            return pool[slot * size * size * size + ((k % size) * size + j % size) * size + i % size]
        }
        let reach = Float(band / 2)
        var worst: Float = 0
        for k in 0..<counts[2] - 1 {
            for j in 0..<counts[1] - 1 {
                for i in 0..<counts[0] - 1 {
                    var nearest = Float.infinity
                    for corner in 0..<8 {
                        nearest = min(nearest, abs(sample(i + (corner & 1), j + ((corner >> 1) & 1), k + (corner >> 2))))
                    }
                    guard nearest <= reach else { continue }
                    for corner in 0..<8 {
                        let (a, b, c) = (corner & 1, (corner >> 1) & 1, corner >> 2)
                        let dx = sample(i + 1, j + b, k + c) - sample(i, j + b, k + c)
                        let dy = sample(i + a, j + 1, k + c) - sample(i + a, j, k + c)
                        let dz = sample(i + a, j + b, k + 1) - sample(i + a, j + b, k)
                        worst = max(worst, dx * dx + dy * dy + dz * dz)
                    }
                }
            }
        }
        return max(1, Double(worst).squareRoot() / spacing)
    }

    public static func == (lhs: DistanceBlocks, rhs: DistanceBlocks) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    /// The size of one block in millimetres.
    public var blockLength: Double { Double(Self.blockSize) * spacing }

    /// The box the samples span: from the first sample to the last.
    public var bounds: BoundingBox {
        let counts = sampleCounts
        let size = Vector3(Double(counts[0] - 1), Double(counts[1] - 1), Double(counts[2] - 1)) * spacing
        return BoundingBox(min: origin, max: origin + size)
    }

    /// How many blocks are stored.
    public var storedBlockCount: Int { pool.count / (Self.blockSize * Self.blockSize * Self.blockSize) }

    /// The memory the tables take (implicit spec §2.1: baked blocks count towards `estimatedBytes`).
    public var estimatedBytes: Int { pool.count * 4 + table.count * 8 + 128 }

    private var sampleCounts: [Int] { blockCounts.map { $0 * Self.blockSize } }

    private func blockNumber(_ bx: Int, _ by: Int, _ bz: Int) -> Int { (bz * blockCounts[1] + by) * blockCounts[0] + bx }

    /// The sample at integer grid position (i, j, k), held to the grid; where its block is not stored, the block's bound.
    func sample(_ i: Int, _ j: Int, _ k: Int) -> Double {
        let counts = sampleCounts
        let (ci, cj, ck) = (min(max(i, 0), counts[0] - 1), min(max(j, 0), counts[1] - 1), min(max(k, 0), counts[2] - 1))
        let size = Self.blockSize
        let block = blockNumber(ci / size, cj / size, ck / size)
        let slot = Int(table[block])
        guard slot >= 0 else { return Double(coarse[block]) }
        let local = ((ck % size) * size + (cj % size)) * size + (ci % size)
        return Double(pool[slot * size * size * size + local])
    }

    /// The baked signed distance at `point`. Inside the grid: trilinear between samples. Outside it: the value at the nearest point of
    /// the grid plus the distance to it (the grid is padded past the surface, so outside it is outside the solid).
    public func value(at point: Vector3) -> Double {
        let box = bounds
        let held = Vector3(min(max(point.x, box.min.x), box.max.x), min(max(point.y, box.min.y), box.max.y),
                           min(max(point.z, box.min.z), box.max.z))
        let outside = (point - held).length
        let grid = (held - origin) * (1 / spacing)
        let counts = sampleCounts
        // Sample centres sit on grid points; clamp the cell so the last sample's neighbour is itself.
        let (fx, fy, fz) = (min(max(grid.x, 0), Double(counts[0] - 1)), min(max(grid.y, 0), Double(counts[1] - 1)),
                            min(max(grid.z, 0), Double(counts[2] - 1)))
        let (ix, iy, iz) = (Int(fx.rounded(.down)), Int(fy.rounded(.down)), Int(fz.rounded(.down)))
        let (tx, ty, tz) = (fx - Double(ix), fy - Double(iy), fz - Double(iz))
        func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let x00 = mix(sample(ix, iy, iz), sample(ix + 1, iy, iz), tx)
        let x10 = mix(sample(ix, iy + 1, iz), sample(ix + 1, iy + 1, iz), tx)
        let x01 = mix(sample(ix, iy, iz + 1), sample(ix + 1, iy, iz + 1), tx)
        let x11 = mix(sample(ix, iy + 1, iz + 1), sample(ix + 1, iy + 1, iz + 1), tx)
        return mix(mix(x00, x10, ty), mix(x01, x11, ty), tz) + outside
    }
}
