import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// Rows x-1, x-2, x-1h and x-3m (plan xp-c, X-C7): the engines side by side on one solid, the mesher alone; x-3m is Metal's own compile of a new shape,
/// the figure the HLSL engine's run-time compile (x-3, task 11) is compared with. A plain `swift test` skips it; `scripts/bench.sh ImplicitBench` on a Mac,
/// `DOCKER_EXTRA="-e METALCREATOR_BENCH=1" scripts/linux-test.sh test -c release --no-parallel --filter ImplicitBenchHLSL` on Linux.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["METALCREATOR_BENCH"] == "1", "set METALCREATOR_BENCH=1"))
struct ImplicitBenchHLSL {
    static func sheet(wall: Double) -> ImplicitSolid {
        .tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: .constant(100)), thickness: .constant(wall),
                          region: BoundingBox(min: Vector3(-50, -50, -50), max: Vector3(50, 50, 50))))
    }

    static let resolution = 100.0 / 128

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func releaseOnly() -> Bool {
        #if DEBUG
        Issue.record("Benchmarks run in a release build: scripts/bench.sh (swift test -c release).")
        return false
        #else
        return true
        #endif
    }

    /// The mesher on `name`'s engine ("CPU" for the CPU evaluator), warm: the median of six runs after one.
    static func time(_ solid: ImplicitSolid, on name: String) async throws -> Double {
        let evaluator: any ImplicitBatchEvaluator = name == "CPU"
            ? CPUBatchEvaluator(solid)
            : await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(name)).evaluator
        let clock = ContinuousClock()
        var samples: [Double] = []
        for round in 0..<7 {
            let start = clock.now
            let mesher = ImplicitMesher(evaluator: evaluator)
            let (_, path) = try await mesher.meshReportingPath(solid, resolution: resolution, quality: .preview)
            if round > 0 { samples.append(milliseconds(clock.now - start)) }
            #expect(name == "CPU" || path == .gpu, "\(name) meshed on the GPU")
        }
        return samples.sorted()[samples.count / 2]
    }

    @Test(arguments: GPUEnginesUnderTest.names + ["CPU"])
    func theFirstPassAndAThicknessEditOnEachEngine(_ name: String) async throws {
        guard Self.releaseOnly() else { return }
        let first = try await Self.time(Self.sheet(wall: 3), on: name)
        let edit = try await Self.time(Self.sheet(wall: 2.5), on: name)
        let digits = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        print("BENCH x-1 \(name): first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median \(first.formatted(digits)) ms")
        print("BENCH x-2 \(name): thickness edit, warm: median \(edit.formatted(digits)) ms")
        if name == "Metal (HLSL)" {
            let verdict = first < 1000 ? "met" : "missed"
            print("BENCH x-1h Metal (HLSL): \(first.formatted(digits)) ms; budget 1000.00 ms: \(verdict)")
            #expect(first < 1000, "x-1h: the generated HLSL on this Mac's GPU misses i-1's 1 s")
        }
    }

    #if canImport(Metal)
    /// x-3m: Metal compiling one new shape, the evaluation pipeline and then the five meshing kernels (a fresh engine each time).
    @Test func metalsCompileOfANewShape() async throws {
        guard Self.releaseOnly(), MetalImplicitEngine.shared != nil else { return }
        let clock = ContinuousClock()
        var evaluation: [Double] = []
        var meshing: [Double] = []
        for round in 0..<5 {
            let engine = try #require(MetalImplicitEngine())
            let solid = Self.sheet(wall: 3 + Double(round))
            let start = clock.now
            let program = try await engine.compile(solid)
            let compiled = clock.now
            let plan = try await BrickPlan.build(for: solid, resolution: 10, using: CPUBatchEvaluator(solid))
            _ = try await engine.meshBricks(program, BrickMeshRequest(plan: plan, snap: true)) { _ in }
            evaluation.append(Self.milliseconds(compiled - start))
            meshing.append(Self.milliseconds(clock.now - compiled))
        }
        let digits = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        print("BENCH x-3m Metal: a new shape's evaluation pipeline median \(evaluation.sorted()[2].formatted(digits)) ms, "
            + "its meshing pipelines and a coarse mesh median \(meshing.sorted()[2].formatted(digits)) ms")
    }
    #endif
}
