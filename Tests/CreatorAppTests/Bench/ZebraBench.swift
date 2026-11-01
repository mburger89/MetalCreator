#if canImport(CreatorOCCT)
import CreatorKernel
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Zebra stripes need a finer display mesh (`DisplayAngle.zebra`, 0.05 rad against the usual 0.5): what that costs on the
/// §7.2 bracket. Release, idle Mac; prints `BENCH zebra-1 …` lines (milliseconds per tessellation and the triangle counts).
/// Recorded, not gated.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct ZebraBench {
    @Test func theBracketTessellatedAtBothAngles() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        let solid = try #require(app.viewport.items.first { !$0.isGuide }?.solid)
        let tolerance = app.viewport.displayTolerance
        let kernel = OCCTKernel()
        let clock = ContinuousClock()
        for (name, angle) in [("0.5 rad", DisplayAngle.standard), ("0.05 rad", DisplayAngle.zebra)] {
            var samples = BenchSamples("zebra-1 bracket tessellation at \(name)")
            var triangles = 0
            for round in 0..<30 {
                let start = clock.now
                let mesh = try await kernel.tessellate(solid, tolerance: tolerance, angle: angle)
                guard round >= 5 else { continue }
                samples.append(from: start, to: clock.now)
                triangles = mesh.indices.count / 3
            }
            #expect(triangles > 0)
            print(samples.line())
            print("BENCH zebra-1 triangles at \(name): \(triangles)")
        }
    }
}
#endif
