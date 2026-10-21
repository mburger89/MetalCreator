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
            let step = max(1, flagged.count / 64)
            let all = grid.points
            points = stride(from: 0, to: flagged.count, by: step).map { all[flagged[$0]] }
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
