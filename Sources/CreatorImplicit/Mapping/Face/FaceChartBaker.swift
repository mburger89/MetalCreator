import CreatorGeometry
import CreatorKernel

/// Measures a face on a grid (implicit spec §3.5): asks the kernel where each sample stands against the face and assembles the chart.
public enum FaceChartBaker {
    /// How many points go to the kernel at once.
    private static let chunk = 8_192

    /// - Parameters:
    ///   - bounds: what the chart covers: the box the solid was baked over.
    ///   - face: the face of `solid`.
    ///   - tolerance: the solid's tolerance; the grid's spacing is the one a bake of it uses (`DistanceBaker.spacing(forTolerance:)`),
    ///     raised until the grid has at most `FaceChartGrid.maximumSamples`.
    public static func bake(bounds: BoundingBox, solid: Solid, face: FaceID, tolerance: Double,
                            kernel: any Kernel) async throws -> FaceChart {
        let facts = try await kernel.faceParametrization(of: face, in: solid)
        let grid = FaceChartGrid(covering: bounds, spacing: DistanceBaker.spacing(forTolerance: tolerance))
        let samples = try await project(grid.points, onto: face, of: solid, kernel: kernel)
        return FaceChartAssembler.assemble(grid: grid, facts: facts, samples: samples)
    }

    private static func project(_ points: [Vector3], onto face: FaceID, of solid: Solid, kernel: any Kernel) async throws -> [FaceSample] {
        var samples: [FaceSample] = []
        samples.reserveCapacity(points.count)
        for start in stride(from: 0, to: points.count, by: chunk) {
            try Task.checkCancellation()
            samples += try await kernel.faceCoordinates(of: Array(points[start..<min(start + chunk, points.count)]), on: face, in: solid)
        }
        return samples
    }
}
