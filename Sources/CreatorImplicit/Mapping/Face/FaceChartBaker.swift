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
        let samples = try await project(grid.points[...], onto: face, of: solid, kernel: kernel, found: [])
        return FaceChartAssembler.assemble(grid: grid, facts: facts, samples: samples)
    }

    /// The kernel's answer for `points`, a chunk at a time. A recursion and not a loop: the Swift 6.4 Windows compiler crashes in
    /// coroutine splitting on an async function that holds a loop's locals across an `await`.
    private static func project(_ points: ArraySlice<Vector3>, onto face: FaceID, of solid: Solid, kernel: any Kernel,
                                found: [FaceSample]) async throws -> [FaceSample] {
        guard !points.isEmpty else { return found }
        try Task.checkCancellation()
        let now = points.prefix(chunk)
        let answer = try await kernel.faceCoordinates(of: Array(now), on: face, in: solid)
        return try await project(points.dropFirst(now.count), onto: face, of: solid, kernel: kernel, found: found + answer)
    }
}
