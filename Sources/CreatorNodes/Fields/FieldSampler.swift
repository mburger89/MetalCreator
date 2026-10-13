import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Samples a field over a batch of points (fields spec §2.2). Every user of a field calls it: Sample Field, Cull by Field and,
/// later, the previews and Field Scatter; nothing evaluates a field point by point.
///
/// The walk visits each node of the expression once and evaluates it over the whole array of points. Loops over points run in
/// chunks of `chunkSize` with a cancellation check between chunks. A value depends on the field and the point alone, never on
/// the rest of the batch, so a batch and the same points one at a time agree exactly, and a longer list changes no earlier
/// sample. Kernel distances go through `cache` when one is given (nodes pass `EvalContext.fieldDistances`).
public enum FieldSampler {
    /// How many points a loop handles between cancellation checks.
    public static let chunkSize = 1024

    /// The field at each of `points`, in order.
    public static func sample(_ field: Field, at points: [Vector3], kernel: any Kernel,
                              cache: FieldDistanceCache? = nil) async throws -> [Double] {
        try Task.checkCancellation()
        guard !points.isEmpty else { return [] }
        return try await Sampling(kernel: kernel, cache: cache).values(of: field, at: points)
    }
}

/// One call of `FieldSampler.sample`: the kernel and cache its distance leaves use.
struct Sampling {
    let kernel: any Kernel
    let cache: FieldDistanceCache?

    // The values of `field` at `points`. One branch per case, with no `default`, so a case added later
    // is a compile error here; that is over the complexity limit.
    // swiftlint:disable:next cyclomatic_complexity
    func values(of field: Field, at points: [Vector3]) async throws -> [Double] {
        switch field {
        case .constant(let value):
            return [Double](repeating: value, count: points.count)
        case .distance(let source, let signed):
            return try await distances(from: points, to: source, signed: signed)
        case .linearGradient(let plane, let length):
            let normal = plane.normal.normalized ?? .zero
            return try FieldSampler.map(points) { (($0 - plane.origin).dot(normal)) / length }
        case .radialGradient(let center, let radius):
            return try FieldSampler.map(points) { ($0 - center).length / radius }
        case .noise(let seed, let scale, let octaves):
            let noise = FieldNoise(seed: seed, scale: scale, octaves: octaves)
            return try FieldSampler.map(points) { noise.value(at: $0) }
        case .image(let image, let plane, let width, let height, let edges):
            let across = plane.xAxis.normalized ?? .zero, up = plane.yAxis.normalized ?? .zero
            return try FieldSampler.map(points) { point in
                let offset = point - plane.origin
                return image.value(u: offset.dot(across) / width + 0.5, v: 0.5 - offset.dot(up) / height, edges: edges)
            }
        case .add(let a, let b):
            return try FieldSampler.combine(try await values(of: a, at: points), try await values(of: b, at: points), +)
        case .multiply(let a, let b):
            return try FieldSampler.combine(try await values(of: a, at: points), try await values(of: b, at: points), *)
        case .minimum(let a, let b):
            return try FieldSampler.combine(try await values(of: a, at: points), try await values(of: b, at: points),
                                         FieldSampler.minimum)
        case .maximum(let a, let b):
            return try FieldSampler.combine(try await values(of: a, at: points), try await values(of: b, at: points),
                                         FieldSampler.maximum)
        case .remap(let inner, let fromLow, let fromHigh, let toLow, let toHigh, let clamped):
            return try FieldSampler.map(try await values(of: inner, at: points)) {
                FieldSampler.remap($0, fromLow: fromLow, fromHigh: fromHigh, toLow: toLow, toHigh: toHigh, clamped: clamped)
            }
        case .clamp(let inner, let low, let high):
            return try FieldSampler.map(try await values(of: inner, at: points)) { FieldSampler.clamp($0, low: low, high: high) }
        case .smoothMinimum(let a, let b, let width):
            return try FieldSampler.combine(try await values(of: a, at: points), try await values(of: b, at: points)) {
                FieldSampler.smoothMinimum($0, $1, width: width)
            }
        }
    }

    private func distances(from points: [Vector3], to source: Field.DistanceSource, signed: Bool) async throws -> [Double] {
        switch source {
        case .point(let target):
            return try FieldSampler.map(points) { ($0 - target).length }
        case .profile(let profile):
            let measure = ProfileDistance(profile)
            return try FieldSampler.map(points) { measure.distance(from: $0) }
        case .kernel(let target):
            if let cache {
                return try await cache.distances(from: points, to: target, signed: signed, kernel: kernel)
            }
            return try await kernel.distances(from: points, to: target, signed: signed)
        }
    }
}
