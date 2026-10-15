import CreatorGeometry
import Foundation

/// Evaluates an implicit solid at a batch of points (implicit spec §4.1). The sparse octree and the mesher call it with thousands of
/// points at a time; `CPUBatchEvaluator` is a complete engine on every platform (implicit spec Errata D11), and `GPUBatchEvaluator`
/// (Task 8) is the fast path where an `ImplicitGPUEngine` exists. Coordinates and values are `Float`, as on the GPU.
public protocol ImplicitBatchEvaluator: Sendable {
    /// The value at each of `points`, in order. Throws `CancellationError` when the task is cancelled between chunks.
    func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float]

    /// "CPU" or the GPU engine's name ("Metal"), for the preview badge and the inspector.
    var engineName: String { get }

    /// The mesh of `request`'s bricks when this evaluator can mesh them itself (a GPU engine can, Errata D13); `nil` when it cannot,
    /// or will not for this request, and the CPU mesher meshes them over `evaluate`. Throws `CancellationError`.
    func meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh?
}

extension ImplicitBatchEvaluator {
    public func meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        nil
    }
}

/// The reference evaluation, in `Double`, spread over the processors.
public struct CPUBatchEvaluator: ImplicitBatchEvaluator {
    public let solid: ImplicitSolid

    public init(_ solid: ImplicitSolid) {
        self.solid = solid
    }

    public var engineName: String { "CPU" }

    /// How many points one task handles between cancellation checks.
    static let chunk = 2048

    public func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try Task.checkCancellation()
        guard points.count > Self.chunk else { return evaluate(points[...]) }
        let solid = solid
        let tasks = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let run = max(Self.chunk, (points.count + tasks - 1) / tasks)
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for start in stride(from: 0, to: points.count, by: run) {
                let slice = points[start..<min(start + run, points.count)]
                group.addTask {
                    var values: [Float] = []
                    values.reserveCapacity(slice.count)
                    let evaluation = CPUEvaluation()
                    for first in stride(from: slice.startIndex, to: slice.endIndex, by: Self.chunk) {
                        try Task.checkCancellation()
                        for point in slice[first..<min(first + Self.chunk, slice.endIndex)] {
                            values.append(Float(evaluation.distance(solid, at: Vector3(Double(point.x), Double(point.y), Double(point.z)))))
                        }
                    }
                    return (start, values)
                }
            }
            var runs: [(Int, [Float])] = []
            for try await result in group { runs.append(result) }
            return runs.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    private func evaluate(_ points: ArraySlice<SIMD3<Float>>) -> [Float] {
        let evaluation = CPUEvaluation()
        return points.map { Float(evaluation.distance(solid, at: Vector3(Double($0.x), Double($0.y), Double($0.z)))) }
    }
}
