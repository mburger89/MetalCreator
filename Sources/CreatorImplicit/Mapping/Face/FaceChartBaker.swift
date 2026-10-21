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
        return try await append(from: 0, of: points, onto: face, of: solid, kernel: kernel, into: samples)
    }

    /// One chunk per step, recursing for the next, so no loop's locals are held across the `await` (Swift 6.4 Windows `CoroFrame.cpp`).
    private static func append(from start: Int, of points: [Vector3], onto face: FaceID, of solid: Solid, kernel: any Kernel,
                               into samples: [FaceSample]) async throws -> [FaceSample] {
        guard start < points.count else { return samples }
        try Task.checkCancellation()
        let end = min(start + chunk, points.count)
        let chunkSamples = try await kernel.faceCoordinates(of: Array(points[start..<end]), on: face, in: solid)
        return try await append(from: start + chunk, of: points, onto: face, of: solid, kernel: kernel, into: samples + chunkSamples)
    }
}
