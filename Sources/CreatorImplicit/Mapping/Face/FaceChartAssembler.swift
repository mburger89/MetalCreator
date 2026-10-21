import CreatorGeometry
import CreatorKernel
import Foundation

/// Turns what the kernel said about a grid of points into a `FaceChart` (implicit spec §3.5): the coordinates in their stored forms,
/// the cells that stretch the map too far, and the distance to them. The kernel is not here, so the same code makes a chart from an
/// analytic surface in a test.
public enum FaceChartAssembler {
    /// - Parameters:
    ///   - grid: where the samples are.
    ///   - facts: how the face is parametrized.
    ///   - samples: the face's answer for each of `grid.points`, in the same order.
    public static func assemble(grid: FaceChartGrid, facts: FaceParametrization, samples: [FaceSample]) -> FaceChart {
        precondition(samples.count == grid.sampleCount, "a face chart needs one sample per grid point")
        let first = encode(samples.map(\.u), middle: facts.uMid, period: facts.uPeriod, scale: facts.uScale)
        let second = encode(samples.map(\.v), middle: facts.vMid, period: facts.vPeriod, scale: facts.vScale)
        let depth = samples.map { Float($0.depth) }
        let analysis = FaceChartAnalysis.run(grid: grid, first: first.samples(radius: turn(facts.uPeriod, facts.uScale)),
                                             second: second.samples(radius: turn(facts.vPeriod, facts.vScale)), depth: depth,
                                             limit: FaceChart.stretchLimit)
        let anySingular = analysis.singularVertices.contains(true)
        var singular: DistanceBlocks?
        var points: [Vector3] = []
        if anySingular {
            let distances = FaceChartAnalysis.distances(from: analysis.singularVertices, grid: grid, cap: FaceChart.singularCap)
            singular = grid.blocks(distances, lipschitz: 3.0.squareRoot())
            let flagged = analysis.singularVertices.indices.filter { analysis.singularVertices[$0] }
            points = coarsePoints(of: flagged, grid: grid)
        }
        func blocks(_ values: [Float]) -> DistanceBlocks { grid.blocks(values.map { $0.isFinite ? $0 : 0 }, lipschitz: 1) }
        func extent(_ values: [Float]) -> Double { values.filter(\.isFinite).map { Double(abs($0)) }.max() ?? 0 }
        let periods = (first: facts.uPeriod.map { $0 * facts.uScale }, second: facts.vPeriod.map { $0 * facts.vScale })
        let extents = (periods.first.map { $0 / 2 } ?? extent(first.primary), periods.second.map { $0 / 2 } ?? extent(second.primary),
                       extent(depth))
        return FaceChart(bounds: grid.bounds, spacing: grid.spacing, kind: facts.kind, hasDegenerateEdge: facts.hasDegenerateEdge,
                         first: blocks(first.primary), firstSine: first.sine.map(blocks), second: blocks(second.primary),
                         secondSine: second.sine.map(blocks), depth: blocks(depth), singular: singular, firstTurn: periods.first,
                         secondTurn: periods.second, slopes: analysis.slopes, extents: extents, singularPoints: points)
    }

    /// The most singular positions kept.
    static let maximumSingularPoints = 4096

    /// A position for each singular sample, thinned only when there are more than `maximumSingularPoints`: then one per bucket of
    /// 2³, 4³, … samples, the smallest bucket that fits. So a region box that holds only a few singular cells still finds one (a
    /// stride over the whole chart could skip them all) and the set is as fine as the cap allows.
    private static func coarsePoints(of flagged: [Int], grid: FaceChartGrid) -> [Vector3] {
        let counts = grid.counts
        var bucket = 1
        while true {
            var seen = Set<Int>()
            var kept: [Int] = []
            for index in flagged {
                let (i, j, k) = (index % counts[0], index / counts[0] % counts[1], index / (counts[0] * counts[1]))
                let key = ((k / bucket) * counts[1] + j / bucket) * counts[0] + i / bucket
                if seen.insert(key).inserted { kept.append(index) }
            }
            if kept.count <= maximumSingularPoints || bucket >= counts.max() ?? 1 {
                return kept.prefix(maximumSingularPoints).map { index in
                    grid.origin + Vector3(Double(index % counts[0]), Double(index / counts[0] % counts[1]),
                                          Double(index / (counts[0] * counts[1]))) * grid.spacing
                }
            }
            bucket *= 2
        }
    }

    /// The length of a radian of a periodic coordinate in millimetres: the turn over 2π; 1 for a coordinate that is not periodic.
    private static func turn(_ period: Double?, _ scale: Double) -> Double {
        period.map { $0 * scale / (2 * Double.pi) } ?? 1
    }

    /// A coordinate in its stored form.
    private struct Encoded {
        var primary: [Float]
        var sine: [Float]?

        func samples(radius: Double) -> FaceChartAnalysis.Samples {
            if let sine { .angle(cosine: primary, sine: sine, radius: radius) } else { .linear(primary) }
        }
    }

    private static func encode(_ values: [Double], middle: Double, period: Double?, scale: Double) -> Encoded {
        guard let period else { return Encoded(primary: values.map { Float(($0 - middle) * scale) }, sine: nil) }
        let angles = values.map { 2 * Double.pi * ($0 - middle) / period }
        return Encoded(primary: angles.map { Float(cos($0)) }, sine: angles.map { Float(sin($0)) })
    }
}
