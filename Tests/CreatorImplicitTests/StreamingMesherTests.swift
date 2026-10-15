import CreatorGeometry
import Foundation
import Synchronization
import Testing
@testable import CreatorImplicit

/// The streamed export's mesher (implicit spec Errata D12, §7): window by window it makes the mesh the whole-mesh mesher makes, never
/// holding more than a window.
struct StreamingMesherTests {
    func streamer(_ solid: ImplicitSolid, windowBricks: Int = 6) -> StreamingMesher {
        StreamingMesher(evaluator: CPUBatchEvaluator(solid), windowBricks: windowBricks, bricksPerBatch: 5)
    }

    func triangleSet(_ mesh: TriangleMesh) -> Set<[SIMD3<Float>]> {
        Set((0..<mesh.triangleCount).map { index in
            let corners = (0..<3).map { mesh.positions[Int(mesh.triangles[3 * index + $0])] }
            // The same triangle from any corner: start at the smallest.
            let keys = corners.map { [$0.x, $0.y, $0.z] }
            let start = (0..<3).min { keys[$0].lexicographicallyPrecedes(keys[$1]) } ?? 0
            return [corners[start], corners[(start + 1) % 3], corners[(start + 2) % 3]]
        })
    }

    @Test func aSphereInManyWindowsIsTheMeshTheWholeMesherMakes() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        var sink = CollectingSink()
        let report = try await streamer(solid).stream(solid, resolution: 0.5, into: &sink)
        let whole = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: 0.5, quality: .export)
        #expect(report.windows >= 4 && sink.windows == report.windows, "\(report.windows) windows")
        let streamed = sink.mesh
        #expect(streamed.vertexCount == whole.vertexCount && streamed.triangleCount == whole.triangleCount)
        #expect(triangleSet(streamed) == triangleSet(whole), "the very same triangles")
        let topology = MeshTopology(streamed)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        #expect(report.vertices == whole.vertexCount && report.triangles == whole.triangleCount)
        #expect(report.sharedVertices > 0, "windows that touch meet in vertices written once")
        #expect(report.vertices + report.sharedVertices > report.vertices && report.windows > 1)
        #expect(report.largestWindow < whole.triangleCount / 2, "memory is a window, not the mesh")
    }

    @Test func aRingAndTwoFarPiecesStreamClosed() async throws {
        let ring = ImplicitSolid.subtract([.cylinder(radius: 8, halfHeight: 3), .cylinder(radius: 4, halfHeight: 5)], blend: .constant(0))
        var sink = CollectingSink()
        _ = try await streamer(ring).stream(ring, resolution: 0.5, into: &sink)
        #expect(MeshTopology(sink.mesh).isClosedManifold && MeshTopology(sink.mesh).eulerCharacteristic == 0)
        let far = ImplicitSolid.moved(.sphere(radius: 3), RigidMove(origin: Vector3(30, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        let pair = ImplicitSolid.union([.sphere(radius: 3), far], blend: .constant(0))
        var apart = CollectingSink()
        _ = try await streamer(pair, windowBricks: 2).stream(pair, resolution: 0.4, into: &apart)
        #expect(MeshTopology(apart.mesh).isClosedManifold && MeshTopology(apart.mesh).eulerCharacteristic == 4)
    }

    @Test func theWindowSizeChangesNothingInTheOutput() async throws {
        let solid = ImplicitFixtures.cylinder
        var sets: [Set<[SIMD3<Float>]>] = []
        for size in [3, 7, 1_000_000] {
            var sink = CollectingSink()
            _ = try await streamer(solid, windowBricks: size).stream(solid, resolution: 0.5, into: &sink)
            sets.append(triangleSet(sink.mesh))
        }
        #expect(sets[0] == sets[1] && sets[1] == sets[2])
    }

    @Test func decimatingEachWindowKeepsTheWholeClosedAndTheShapeWithinTheTolerance() async throws {
        let solid = ImplicitSolid.box(halfSize: Vector3(6, 4, 3), cornerRadius: 0)
        var plain = CollectingSink()
        _ = try await streamer(solid, windowBricks: 4).stream(solid, resolution: 0.4, into: &plain)
        var slim = CollectingSink()
        let report = try await streamer(solid, windowBricks: 4).stream(solid, resolution: 0.4, stages: [.decimate(tolerance: 0.02)],
                                                                         into: &slim)
        #expect(report.windows >= 3)
        let topology = MeshTopology(slim.mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2, "\(topology)")
        #expect(slim.mesh.triangleCount < plain.mesh.triangleCount / 3, "\(plain.mesh.triangleCount) → \(slim.mesh.triangleCount)")
        #expect(abs(slim.mesh.signedVolume - plain.mesh.signedVolume) / plain.mesh.signedVolume < 0.002, "the volume hardly moves")
        #expect(report.triangles == slim.mesh.triangleCount && report.vertices == slim.mesh.vertexCount)
    }

    @Test func aCancelStopsBetweenWindowsAndTheSinkIsLeftForTheCallerToCancel() async {
        let solid = ImplicitSolid.sphere(radius: 10)
        let task = Task {
            var sink = CollectingSink()
            let seen = Mutex(0)
            do {
                _ = try await streamer(solid, windowBricks: 4).stream(solid, resolution: 0.5, into: &sink) { fraction in
                    if fraction > 0.2 { seen.withLock { $0 += 1 } }
                    if fraction > 0.2 { withUnsafeCurrentTask { $0?.cancel() } }
                }
                return (false, sink.windows)
            } catch is CancellationError {
                return (true, sink.windows)
            } catch {
                return (false, -1)
            }
        }
        let (cancelled, windows) = await task.value
        #expect(cancelled && windows >= 1 && windows < 20)
    }

    @Test func aSecondMeshInTheSameObjectContinuesTheNumbering() async throws {
        let first = ImplicitSolid.sphere(radius: 4)
        let second = ImplicitSolid.sphere(radius: 3)
        var sink = CollectingSink()
        let one = try await streamer(first).stream(first, resolution: 0.5, into: &sink)
        let two = try await streamer(second).stream(second, resolution: 0.5, startingAt: sink.vertexCount, into: &sink)
        #expect(one.vertices + two.vertices == sink.vertexCount)
        #expect(MeshTopology(sink.mesh).isClosedManifold && MeshTopology(sink.mesh).eulerCharacteristic == 4, "two closed shells")
    }

    @Test func windowsWhoseSeamVerticesDifferInTheirBitsAreRefusedNotWrittenOpen() async {
        // An evaluator whose answers drift from one call to the next stands for one that does not return the same bits for the same
        // point in two batches: the seam cannot be welded, and the streamer says so rather than write a file that is not watertight.
        let solid = ImplicitSolid.sphere(radius: 10)
        let drifting = DriftingEvaluator(CPUBatchEvaluator(solid))
        var sink = CollectingSink()
        await #expect(throws: ImplicitMeshingError.seamsDidNotJoin) {
            try await StreamingMesher(evaluator: drifting, windowBricks: 6, bricksPerBatch: 5).stream(solid, resolution: 0.5, into: &sink)
        }
    }

    @Test func aSolidWithNoSurfaceIsRefused() async {
        let solid = ImplicitSolid.sphere(radius: 0.01)
        var sink = CollectingSink()
        await #expect(throws: ImplicitMeshingError.empty) { try await streamer(solid).stream(solid, resolution: 0.5, into: &sink) }
    }

    @Test func progressRunsFromZeroToOne() async throws {
        let solid = ImplicitSolid.sphere(radius: 6)
        var sink = CollectingSink()
        let seen = Mutex<[Double]>([])
        _ = try await streamer(solid, windowBricks: 4).stream(solid, resolution: 0.5, into: &sink) { value in
            seen.withLock { $0.append(value) }
        }
        let values = seen.withLock { $0 }
        #expect(values.first == 0 && values.last == 1 && values == values.sorted() && values.count > 3)
    }

    @Test func aStreamToAFileHoldsTheSameTrianglesAsTheMesh() async throws {
        let solid = ImplicitSolid.sphere(radius: 6)
        let url = URL.temporaryDirectory.appending(path: "stream-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        try writer.beginObject(name: "Ball")
        _ = try await streamer(solid, windowBricks: 4).stream(solid, resolution: 0.5, into: &writer)
        try writer.endObject()
        try writer.finish()
        let model = try #require(ThreeMFReading.read(try ZipReader(contentsOf: url).contents(of: "3D/3dmodel.model")))
        let object = try #require(model.objects.first)
        let whole = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: 0.5, quality: .export)
        #expect(object.vertices.count == whole.vertexCount && object.triangles.count == whole.triangleCount)
        let mesh = TriangleMesh(positions: object.vertices.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) },
                                triangles: object.triangles.flatMap { $0.map { UInt32($0) } })
        #expect(MeshTopology(mesh).isClosedManifold && MeshTopology(mesh).eulerCharacteristic == 2)
    }
}

/// Answers of the wrapped evaluator, each call shifted a little further than the last.
private final class DriftingEvaluator: ImplicitBatchEvaluator {
    let base: CPUBatchEvaluator
    let calls = Mutex(0)
    var engineName: String { "drifting" }

    init(_ base: CPUBatchEvaluator) { self.base = base }

    func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        let call = calls.withLock { value -> Int in
            value += 1
            return value
        }
        return try await base.evaluate(points).map { $0 + 1e-3 * Float(call) }
    }
}
