import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Writes an export's meshes straight to an STL or 3MF file (implicit spec Errata D12): each Output node is one object, its solids
/// tessellated by the kernel, its meshes written as they are, and its streams meshed window by window by `StreamingMesher`, so the
/// file is never in memory. Memory is the largest window. A cancel (the task's) or an error removes the half-written file.
enum StreamedExport {
    /// What one Output node holds.
    struct Output: Sendable {
        var name: String
        var solids: [Solid]
        var meshes: [any MeshPayload]
    }

    /// The tolerance solids are tessellated at when they share a file with meshes, in millimetres.
    static let tessellationTolerance = 0.01

    /// - Parameters:
    ///   - progress: the fraction of the streams done, 0 to 1, from any thread.
    /// - Throws: `CancellationError`, `ImplicitMeshingError`, `ZipError`, `MeshDecimator.Failure` and the kernel's errors.
    static func write(_ outputs: [Output], as kind: ExportKind, to url: URL, kernel: any Kernel, engine: ImplicitEngineChoice,
                      progress: @escaping @Sendable (Double) -> Void) async throws {
        switch kind {
        case .stl:
            var sink = try STLFileWriter(destination: url)
            try await write(outputs, into: &sink, kernel: kernel, engine: engine, progress: progress)
        case .threeMF:
            var sink = ThreeMFWriter(destination: url)
            try await write(outputs, into: &sink, kernel: kernel, engine: engine, progress: progress)
        case .step:
            preconditionFailure("STEP is written by the kernel")
        }
    }

    private static func write(_ outputs: [Output], into sink: inout some MeshSink, kernel: any Kernel, engine: ImplicitEngineChoice,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        let streams = outputs.reduce(0) { $0 + $1.meshes.filter { $0 is MeshStream }.count }
        var finished = 0
        do {
            progress(0)
            for output in outputs {
                try sink.beginObject(name: output.name)
                for solid in output.solids {
                    let display = try await kernel.tessellate(solid, tolerance: tessellationTolerance)
                    let positions = display.positions.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
                    try sink.add(MeshWindow(positions: positions, triangles: display.indices, startingAt: sink.vertexCount))
                }
                for payload in output.meshes {
                    if let mesh = payload as? TriangleMesh {
                        try sink.add(MeshWindow(positions: mesh.positions, triangles: mesh.triangles, startingAt: sink.vertexCount))
                    } else if let stream = payload as? MeshStream {
                        let done = finished
                        try await write(stream, into: &sink, engine: engine) { fraction in
                            progress((Double(done) + fraction) / Double(max(streams, 1)))
                        }
                        finished += 1
                    }
                }
                try sink.endObject()
            }
            try Task.checkCancellation()
            try sink.finish()
            progress(1)
        } catch {
            sink.cancel()
            throw error
        }
    }

    private static func write(_ stream: MeshStream, into sink: inout some MeshSink, engine: ImplicitEngineChoice,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        let selection = await ImplicitEvaluators.make(for: stream.solid, choice: engine)
        let mesher = StreamingMesher(evaluator: selection.evaluator)
        _ = try await mesher.stream(stream.solid, resolution: stream.resolution, stages: stream.stages, startingAt: sink.vertexCount,
                                    into: &sink, progress: progress)
    }
}
