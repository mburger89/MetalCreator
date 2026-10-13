import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// Sampling a field over a mesh's vertices and a slice's grid (fields spec §6): one call to the sampler each.
struct FieldPreviewSamplerTests {
    let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)

    @Test func theTintIsTheFieldAtEachVertexWithItsExtent() async throws {
        let points = (0..<5).map { Vector3(Double($0) * 10, 0, 0) }
        let tint = try await FieldPreviewSampler.tint(of: .radialGradient(center: .zero, radius: 20), at: points, kernel: FakeKernel())
        #expect(tint.values == [0, 0.5, 1, 1.5, 2] && tint.extent == 0...2 && !tint.isCoarse)
    }

    @Test func aBigMeshIsSampledCoarselyAndSaysSo() async throws {
        let points = (0..<100).map { Vector3(Double($0), 0, 0) }
        let tint = try await FieldPreviewSampler.tint(of: .radialGradient(center: .zero, radius: 10), at: points, limit: 25,
                                                      kernel: FakeKernel())
        #expect(tint.isCoarse && tint.values.count == 100)
        // Sampled: every 4th vertex (0, 4, ..., 96), valued x / 10. The rest take the nearest sampled one, ties to the lower.
        func expected(_ vertex: Int) -> Float {
            let nearest: Int
            switch vertex % 4 {
            case 0: nearest = vertex
            case 1, 2: nearest = vertex - vertex % 4
            default: nearest = min(vertex + 1, 96)
            }
            return Float(Double(nearest) / 10)
        }
        #expect(tint.values == (0..<100).map(expected))
        #expect(Array(tint.values[0..<9]) == [0, 0, 0, 0.4, 0.4, 0.4, 0.4, 0.8, 0.8], "vertex 1 takes 0, 2 ties to 0, 3 takes 4")
        #expect(Array(tint.values[96...]) == [9.6, 9.6, 9.6, 9.6], "past the last sampled vertex, that one's value")
        #expect(tint.extent?.lowerBound == 0 && (tint.extent?.upperBound ?? 0) > 9)
        let whole = try await FieldPreviewSampler.tint(of: .radialGradient(center: .zero, radius: 10), at: points, limit: 100,
                                                       kernel: FakeKernel())
        #expect(!whole.isCoarse)
    }

    @Test func valuesThatAreNotNumbersAreNotInTheExtent() async throws {
        let nothing = try await FieldPreviewSampler.tint(of: .constant(.nan), at: [.zero, .unitX], kernel: FakeKernel())
        #expect(nothing.extent == nil)
        let some = try await FieldPreviewSampler.tint(of: .remap(.radialGradient(center: .zero, radius: 1), fromLow: 0, fromHigh: 0,
                                                                 toLow: 0, toHigh: 1, clamped: false),
                                                      at: [.zero], kernel: FakeKernel())
        // A zero-width input range gives the output's low end (toLow = 0), a finite value with a one-point extent.
        #expect(some.values == [0] && some.extent == 0...0)
    }

    @Test func noVerticesGiveNoValues() async throws {
        let tint = try await FieldPreviewSampler.tint(of: .constant(1), at: [], kernel: FakeKernel())
        #expect(tint.values.isEmpty && tint.extent == nil && !tint.isCoarse)
    }

    @Test func aCancelledSamplingStops() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FieldPreviewSampler.tint(of: .constant(1), at: [.zero], kernel: FakeKernel())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func theGridIsTheFieldAtTheSlicesSamplePoints() async throws {
        let slice = ViewportSlice(origin: Vector3(0, 0, 15), xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 4, columns: 2,
                                  rows: 2, values: [], ramp: ramp)
        let grid = try await FieldPreviewSampler.gridValues(of: .linearGradient(plane: .yz, length: 10), in: slice, kernel: FakeKernel())
        #expect(grid.values == [-0.5, 0.5, -0.5, 0.5], "x runs -5, 5 along each row; the gradient is x / 10")
        #expect(grid.extent == -0.5...0.5)
    }
}
