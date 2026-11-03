import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Writes an export's meshes straight to an STL or 3MF file (implicit spec Errata D12): each Output node is one object (one per mesh when it holds several), its solids
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
    /// - Throws: `CancellationError`, `ImplicitMeshingError`, `ZipError` and the kernel's errors.
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
            let run = Run(kernel: kernel, engine: engine, streams: streams, progress: progress)
            var index = 0
            while index < outputs.count {
                try await writeOutput(outputs[index], into: &sink, run: run, finished: &finished)
                index += 1
            }
            try Task.checkCancellation()
            try sink.finish()
            progress(1)
        } catch {
            sink.cancel()
            throw error
        }
    }

    /// What every Output of a write shares.
    private struct Run: Sendable {
        var kernel: any Kernel
        var engine: ImplicitEngineChoice
        var streams: Int
        var progress: @Sendable (Double) -> Void
    }

    /// One Output's objects. An Output holding several meshes (an imported 3MF's objects) keeps one object each, named "Part 1",
    /// "Part 2" and so on; its solids, if any, go in the first. One mesh, or none, is the Output's one object. The loop holds no
    /// local across an `await` and the synchronous work is in `add(_:to:)` (the Windows 6.4 compiler's coroutine splitting, CLAUDE.md).
    private static func writeOutput(_ output: Output, into sink: inout some MeshSink, run: Run, finished: inout Int) async throws {
        let split = output.meshes.count > 1
        try sink.beginObject(name: split ? "\(output.name) 1" : output.name)
        var solidIndex = 0
        while solidIndex < output.solids.count {
            let display = try await run.kernel.tessellate(output.solids[solidIndex], tolerance: tessellationTolerance)
            try add(display, to: &sink)
            solidIndex += 1
        }
        var number = 0
        while number < output.meshes.count {
            try Task.checkCancellation()
            if split, number > 0 {
                try sink.endObject()
                try sink.beginObject(name: "\(output.name) \(number + 1)")
            }
            let payload = output.meshes[number]
            if let mesh = payload as? TriangleMesh {
                try sink.add(MeshWindow(positions: mesh.positions, triangles: mesh.triangles, startingAt: sink.vertexCount))
            } else if let stream = payload as? MeshStream {
                try await write(stream, into: &sink, run: run, finishedBefore: finished)
                finished += 1
            }
            number += 1
        }
        try sink.endObject()
    }

    private static func add(_ display: DisplayMesh, to sink: inout some MeshSink) throws {
        let positions = display.positions.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
        try sink.add(MeshWindow(positions: positions, triangles: display.indices, startingAt: sink.vertexCount))
    }

    private static func write(_ stream: MeshStream, into sink: inout some MeshSink, run: Run, finishedBefore: Int) async throws {
        let (streams, progress) = (run.streams, run.progress)
        let overall: @Sendable (Double) -> Void = { fraction in
            progress((Double(finishedBefore) + fraction) / Double(max(streams, 1)))
        }
        // The GPU engine supplies the values (the CPU mesher still builds the triangles: `StreamingMesher` does not use `meshBricks`). The
        // windows are welded by the exact bits of their shared vertices, so the evaluator must return one answer per point whatever the
        // batch: `StreamingMesherGPUTests` holds the GPU's to that, and the streamer refuses (`seamsDidNotJoin`) rather than write a
        // seam that did not weld. All-CPU values cost 295 s against 40.6 s here on `ImplicitBench` i-4 (budget 60 s).
        let selection = await ImplicitEvaluators.make(for: stream.solid, choice: run.engine)
        let mesher = StreamingMesher(evaluator: selection.evaluator)
        _ = try await mesher.stream(stream.solid, resolution: stream.resolution, stages: stream.stages, startingAt: sink.vertexCount,
                                    into: &sink, progress: overall)
    }
}
