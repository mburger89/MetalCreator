import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Row i-8 of `ImplicitBench`: the two checks of a skinned gyroid sheet (implicit spec Errata D18).
extension ImplicitBench {
    @Test func theChecksOfASkinnedSheet() async throws {
        guard Bench.requireRelease() else { return }
        let part = ImplicitBenchFixtures.sheet(side: 30, cell: 10, wall: 1.2, skin: 1.5, exportResolution: 0.3)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(part.graph, demand: [part.output.id], meshQuality: .export)
        guard case .mesh(let payload)? = report.results[part.output.id]?.outputs?["mesh"]?.items.first,
              let mesh = payload as? TriangleMesh else {
            Issue.record("no mesh: \(String(describing: report.results[part.output.id]?.state))")
            return
        }
        let clock = ContinuousClock()
        var traps = BenchSamples("i-8 Check Trapped Volumes of a \(mesh.triangleCount.formatted(.number.grouping(.never))) triangle sheet")
        var thin = BenchSamples("i-8 Check Thin Walls of the same mesh")
        var result = (voids: 0, places: 0)
        for round in 0..<3 {
            let start = clock.now
            result.voids = try TrappedVolumeCheck.run(mesh).voidCount
            let middle = clock.now
            result.places = try ThinWallCheck.run(mesh, minimum: 0.4).places
            if round >= 1 {
                traps.append(from: start, to: middle)
                thin.append(from: middle, to: clock.now)
            }
        }
        print(traps.line())
        print(thin.line())
        print("BENCH i-8 voids \(result.voids), thin places \(result.places)")
        #expect(MeshTopology(mesh).isClosedManifold)
    }

    /// A 150 mm cube, the largest part that keeps 0.5 mm cells, meshed coarsely (its faces are flat), solid or with a 120 mm cavity.
    static func cube(hollow: Bool) async throws -> TriangleMesh {
        let outer = ImplicitSolid.box(halfSize: Vector3(75, 75, 75), cornerRadius: 0)
        let part = hollow ? .subtract([outer, .box(halfSize: Vector3(60, 60, 60), cornerRadius: 0)], blend: .constant(0)) : outer
        return try await ImplicitMesher(evaluator: CPUBatchEvaluator(part)).mesh(part, resolution: 7, quality: .export)
    }

    /// Row i-7s: Check Trapped Volumes on a solid 150 mm cube. The interior is one pocket of about 27 million cells that `EnclosedVoids`
    /// judges material from its first 4,096 listed cells and then stops listing (listing all of it peaked at 603 MB, past D16's 450 MB);
    /// i-7 measured only a hollow cube filled directly. Run it alone (`--filter theChecksOfASolid150mmCube`) for a peak resident size
    /// that is its own.
    @Test func theChecksOfASolid150mmCube() async throws {
        guard Bench.requireRelease() else { return }
        try await Self.measureCube(hollow: false, row: "i-7s", expectedVoids: 0)
    }

    /// Row i-7h: the same on a hollow cube (one real void).
    @Test func theChecksOfAHollow150mmCube() async throws {
        guard Bench.requireRelease() else { return }
        try await Self.measureCube(hollow: true, row: "i-7h", expectedVoids: 1)
    }

    static func measureCube(hollow: Bool, row: String, expectedVoids: Int) async throws {
        let mesh = try await cube(hollow: hollow)
        let before = ImplicitBenchFixtures.peakMemory
        let clock = ContinuousClock()
        let start = clock.now
        let voids = try TrappedVolumeCheck.run(mesh).voidCount
        let elapsed = clock.now - start
        let peak = ImplicitBenchFixtures.peakMemory
        let megabytes = { (bytes: Int) in (Double(bytes) / 1_000_000).formatted(.number.precision(.fractionLength(0))) }
        print("BENCH \(row) \(mesh.triangleCount) triangles, \(voids) void, \(elapsed); peak resident \(megabytes(peak)) MB "
            + "(\(megabytes(before)) MB before the check)")
        #expect(voids == expectedVoids)
    }
}
