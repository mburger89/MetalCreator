import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

/// Samples a field for the previews with the one entry point (`FieldSampler.sample`), off the main actor's way: the tint over a
/// mesh's vertices, coarsely over `limit` vertices (D14), and the slice's grid.
enum FieldPreviewSampler {
    static func tint(of field: Field, at positions: [Vector3], limit: Int = CoarseSampling.vertexLimit, kernel: any Kernel,
                     cache: FieldDistanceCache? = nil) async throws -> FieldTint {
        let indices = CoarseSampling.sampledIndices(count: positions.count, limit: limit)
        let isCoarse = indices.count < positions.count
        let points = isCoarse ? indices.map { positions[$0] } : positions
        let sampled = try await FieldSampler.sample(field, at: points, kernel: kernel, cache: cache)
        let values = isCoarse ? try CoarseSampling.expand(positions: positions, sampled: indices, values: sampled)
                              : sampled.map { Float($0) }
        return FieldTint(values: values, extent: extent(of: sampled), isCoarse: isCoarse)
    }

    /// The field at the slice's grid samples (`ViewportSlice.samplePoints()`), in `values`' order, and their extent.
    static func gridValues(of field: Field, in slice: ViewportSlice, kernel: any Kernel,
                           cache: FieldDistanceCache? = nil) async throws -> (values: [Float], extent: ClosedRange<Double>?) {
        let sampled = try await FieldSampler.sample(field, at: slice.samplePoints(), kernel: kernel, cache: cache)
        return (sampled.map { Float($0) }, extent(of: sampled))
    }

    /// The smallest to the largest finite value, or `nil` when there is none.
    static func extent(of values: [Double]) -> ClosedRange<Double>? {
        var low = Double.infinity
        var high = -Double.infinity
        for value in values where value.isFinite {
            low = min(low, value)
            high = max(high, value)
        }
        return low <= high ? low...high : nil
    }
}
