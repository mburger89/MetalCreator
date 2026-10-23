import CreatorGeometry
import Foundation
import Testing
#if canImport(Metal)
import Metal
#endif
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
    /// Five shapes whose generated source differs from each other and from `sheet(wall:)` (x-1 and x-2 already compiled that one in this process):
    /// a number is not part of a shape, so each round varies the surface type or the form.
    static func distinctShapes() -> [ImplicitSolid] {
        let region = BoundingBox(min: Vector3(-50, -50, -50), max: Vector3(50, 50, 50))
        let kinds: [(TPMSType, TPMSForm)] = [
            (.schwarzP, .sheet), (.diamond, .sheet), (.neovius, .sheet), (.lidinoid, .sheet), (.gyroid, .network),
        ]
        return kinds.map { type, form in
            .tpms(TPMSLattice(type: type, form: form, cells: LatticeCells(size: .constant(100)), thickness: .constant(3), region: region))
        }
    }

    /// Metal compiling `source` to a pipeline state for each of `names`, in milliseconds. Every kernel gets a fresh per-run name and the library a
    /// per-run literal, so the AIR (not only the source text) is unseen and no source, library or pipeline cache can answer: this is a real compile.
    static func compileMilliseconds(_ source: String, kernels names: [String], on device: any MTLDevice) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        // A comment only changes the source text and is gone in the AIR, so the backend (AIR to GPU binary) could still be answered by a cache an
        // earlier run filled. So the text is made unique where it survives into the AIR: every kernel gets a per-run name, and a kernel stores a
        // per-run literal, which changes the library's bitcode and each function's name.
        let tag = UUID().uuidString.replacing("-", with: "")
        var unique = source
        for name in names { unique = unique.replacing(name, with: "\(name)_\(tag)") }
        unique += "\nkernel void benchTag_\(tag)(device uint* out [[buffer(0)]]) { out[0] = \(UInt32.random(in: 1...UInt32.max))u; }\n"
        let library = try await device.makeLibrary(source: unique, options: nil)
        for name in names {
            let function = try #require(library.makeFunction(name: "\(name)_\(tag)"))
            _ = try await device.makeComputePipelineState(function: function)
        }
        return milliseconds(clock.now - start)
    }

    /// x-3m: Metal compiling one new shape, uncached: the evaluation kernel, then the five meshing kernels (the evaluation source with the meshing
    /// library appended). Five different shapes, each with unique text. Reported as first, median and max.
    @Test func metalsCompileOfANewShape() async throws {
        guard Self.releaseOnly(), let device = MTLCreateSystemDefaultDevice() else { return }
        var evaluation: [Double] = []
        var meshing: [Double] = []
        for solid in Self.distinctShapes() {
            let program = try ImplicitCompiler.compile(solid)
            evaluation.append(try await Self.compileMilliseconds(program.source, kernels: [CompiledImplicit.kernelName], on: device))
            meshing.append(try await Self.compileMilliseconds(ImplicitMeshShaderLibrary.source(extending: program),
                                                              kernels: ImplicitMeshShaderLibrary.kernelNames, on: device))
        }
        let digits = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        func summary(_ values: [Double]) -> String {
            let median = values.sorted()[2]
            let slowest = values.max() ?? 0
            return "first \(values[0].formatted(digits)) ms, median \(median.formatted(digits)) ms, max \(slowest.formatted(digits)) ms"
        }
        print("BENCH x-3m Metal: a new shape, uncached source: evaluation kernel \(summary(evaluation)); "
            + "the five meshing kernels \(summary(meshing))")
    }
    #endif
}
