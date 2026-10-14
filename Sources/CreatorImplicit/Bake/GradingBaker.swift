import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Makes a `Grading` from a field (implicit spec §3.3, §4.1): bakes the field's distances to solids, face sets and edge sets (which
/// need the kernel) onto grids over the region the setting applies to, and works out the range and the slope bound the solid's
/// bounds and lipschitz constant are made from.
public enum GradingBaker {
    /// The number of cells across the longest side of a baked distance grid.
    public static let cellsAcross = 40
    /// How many points go to the kernel at once.
    private static let chunk = 16_384

    /// - Parameters:
    ///   - field: the setting's field.
    ///   - region: the box the setting is read in (the solid's bounds, widened by what the setting itself adds).
    ///   - kernel: measures distances to solids.
    ///   - cache: the evaluator's cache of kernel distances.
    public static func grading(for field: Field, over region: BoundingBox, kernel: any Kernel,
                               cache: FieldDistanceCache? = nil) async throws -> Grading {
        if case .constant(let value) = field { return .constant(value) }
        var baked: [Grading.Baked] = []
        for (target, signed) in kernelLeaves(of: field) {
            try Task.checkCancellation()
            baked.append(Grading.Baked(target: target.identity, signed: signed,
                                       blocks: try await bake(target, signed: signed, over: region, kernel: kernel, cache: cache)))
        }
        // `Field.slopeBound` counts a distance leaf as slope 1, but a baked grid interpolates trilinearly and may be steeper; each
        // baked leaf adds what it exceeds 1 by, so the bound stays conservative and `BrickPlan` never prunes a crossed brick.
        let slope = field.slopeBound.value + baked.reduce(0) { $0 + max(0, $1.blocks.lipschitz - 1) }
        var grading = Grading(field: field, baked: baked, range: 0...0, slope: slope)
        if let known = field.valueRange {
            grading.range = known
            return grading
        }
        // No known range: sample a coarse grid and widen the extremes by what the slope allows between samples.
        let steps = 8
        let cell = region.size * (1 / Double(steps))
        let evaluation = CPUEvaluation()
        var low = Double.infinity, high = -Double.infinity
        for i in 0...steps {
            for j in 0...steps {
                for k in 0...steps {
                    let point = region.min + Vector3(cell.x * Double(i), cell.y * Double(j), cell.z * Double(k))
                    let value = evaluation.value(grading, at: point)
                    guard value.isFinite else { continue }
                    low = min(low, value)
                    high = max(high, value)
                }
            }
        }
        guard low <= high else { return grading }
        let slack = slope * cell.length / 2
        grading.range = (low - slack)...(high + slack)
        return grading
    }

    /// The distinct kernel distances in a field, in order of first appearance.
    static func kernelLeaves(of field: Field) -> [(DistanceTarget, signed: Bool)] {
        var found: [(DistanceTarget, signed: Bool)] = []
        func walk(_ field: Field) {
            if case .distance(.kernel(let target), let signed) = field,
               !found.contains(where: { $0.0.identity == target.identity && $0.signed == signed }) {
                found.append((target, signed))
            }
            field.children.forEach(walk)
        }
        walk(field)
        return found
    }

    /// The distance to `target` on a grid over `region`, every block stored.
    private static func bake(_ target: DistanceTarget, signed: Bool, over region: BoundingBox, kernel: any Kernel,
                             cache: FieldDistanceCache?) async throws -> DistanceBlocks {
        let size = DistanceBlocks.blockSize
        let longest = max(region.size.x, region.size.y, region.size.z, 1e-6)
        let spacing = longest / Double(cellsAcross)
        let counts = [region.size.x, region.size.y, region.size.z].map { max(1, Int(($0 / (spacing * Double(size))).rounded(.up))) }
        let samples = counts.map { $0 * size }
        var points: [Vector3] = []
        points.reserveCapacity(samples.reduce(1, *))
        // Blocks in order, and the samples of each in order.
        for bz in 0..<counts[2] {
            for by in 0..<counts[1] {
                for bx in 0..<counts[0] {
                    for z in 0..<size {
                        for y in 0..<size {
                            for x in 0..<size {
                                points.append(region.min + Vector3(Double(bx * size + x), Double(by * size + y),
                                                                   Double(bz * size + z)) * spacing)
                            }
                        }
                    }
                }
            }
        }
        var pool: [Float] = []
        pool.reserveCapacity(points.count)
        for start in stride(from: 0, to: points.count, by: chunk) {
            try Task.checkCancellation()
            let slice = Array(points[start..<min(start + chunk, points.count)])
            let values: [Double]
            if let cache {
                values = try await cache.distances(from: slice, to: target, signed: signed, kernel: kernel)
            } else {
                values = try await kernel.distances(from: slice, to: target, signed: signed)
            }
            pool += values.map(Float.init)
        }
        let blockTotal = counts.reduce(1, *)
        return DistanceBlocks(origin: region.min, spacing: spacing, blockCounts: counts, table: (0..<blockTotal).map(Int32.init),
                              pool: pool, coarse: [Float](repeating: 0, count: blockTotal), band: region.size.length)
    }
}
