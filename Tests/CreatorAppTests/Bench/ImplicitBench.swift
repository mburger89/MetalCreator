import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Implicit spec §6, rows i-1 to i-4 (i-5 and i-6 belong to 7c-3). Release, idle Mac, `scripts/bench.sh ImplicitBench`; each prints
/// `BENCH i-…` lines, with a row's budget judged on the median:
/// - i-1: the first preview pass of the sheet (a noise sheet through a 100 mm cube; see `ImplicitBenchFixtures`) on a fresh
///   evaluator, the GPU's pipelines already compiled: under 1 s. The very first pass of the process, which compiles them, is printed
///   too and not judged.
/// - i-2: a thickness edit (the gap between the two levels) on a warm evaluator, so the noise and the cube are cached and no shader
///   is recompiled: one coarse pass under 100 ms.
/// - i-1m: the same first pass made by the mesher alone, on the GPU mesher and on the CPU mesher over the GPU's values (meshing
///   before Errata D13), to see what GPU meshing bought; i-2 is that coarse pass again. Not judged. The run also checks the pass was
///   made on the GPU, since a fall-back to the CPU is silent.
/// - i-3: To Implicit of the slice's bracket on OCCT at the default tolerance, the bake cache emptied each time: under 500 ms.
/// - i-4: the export of i-1 at 0.1 mm to an STL, the whole pipeline: under 60 s and a peak memory under 4 GB.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct ImplicitBench {
    static let firstPassBudget = 1000.0
    static let editBudget = 100.0
    static let bakeBudget = 500.0
    static let exportBudget = 60_000.0
    static let memoryBudget = 4_000_000_000

    @Test func theFirstPreviewPassOfASheetFillingACube() async throws {
        guard Bench.requireRelease() else { return }
        let sheet = ImplicitBenchFixtures.sheet()
        let clock = ContinuousClock()
        var cold = BenchSamples("i-1 first preview pass of a 100 mm sheet, cold (shaders compiled)")
        var warm = BenchSamples("i-1 first preview pass of a 100 mm sheet")
        let madeBefore = await Self.meshesMade()
        for round in 0..<8 {
            let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel(), implicitEngine: .automatic)
            let start = clock.now
            let report = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id])
            if round == 0 { cold.append(from: start, to: clock.now) } else if round >= 2 { warm.append(from: start, to: clock.now) }
            #expect(report.results[sheet.output.id]?.state.isSuccess == true)
        }
        print(cold.line())
        print(warm.line(budget: Self.firstPassBudget))
        await Self.expectMeshedOnTheGPU(since: madeBefore, atLeast: 8, row: "i-1")
    }

    @Test func aThicknessEditIsOneCoarsePassWithNoRecompile() async throws {
        guard Bench.requireRelease() else { return }
        let sheet = ImplicitBenchFixtures.sheet()
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel(), implicitEngine: .automatic)
        _ = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id])
        let madeBefore = await Self.meshesMade()
        let clock = ContinuousClock()
        var samples = BenchSamples("i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile)")
        var graph = sheet.graph
        for round in 0..<25 {
            graph.nodes[sheet.levels.id]?.inputValues["step"] = .number(-0.1 - 0.001 * Double(round + 1))
            let start = clock.now
            let report = try await evaluator.evaluate(graph, demand: [sheet.output.id])
            guard round >= 3 else { continue }
            samples.append(from: start, to: clock.now)
            #expect(report.evaluatedNodes.count == 5)
        }
        print(samples.line(budget: Self.editBudget))
        await Self.expectMeshedOnTheGPU(since: madeBefore, atLeast: 25, row: "i-2")
    }

    @Test func theFirstPassOnTheGPUMesherAndOnTheCPUMesherOverGPUValues() async throws {
        guard Bench.requireRelease() else { return }
        let solid = try await ImplicitBenchFixtures.solid(of: ImplicitBenchFixtures.sheet())
        let resolution = PreviewSchedule(.automatic).firstResolution(for: solid.bounds)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic)
        guard selection.evaluator.engineName != "CPU" else {
            print("BENCH i-1m skipped: this machine has no GPU engine")
            return
        }
        let clock = ContinuousClock()
        let size = resolution.formatted(.number.precision(.fractionLength(2)))
        var gpu = BenchSamples("i-1m first pass of the sheet at \(size) mm, GPU mesher")
        var cpu = BenchSamples("i-1m the same pass, CPU mesher over the GPU's values (before D13)")
        var triangles = (gpu: 0, cpu: 0)
        for round in 0..<8 {
            let gpuStart = clock.now
            let onGPU = try await ImplicitMesher(evaluator: selection.evaluator)
                .meshReportingPath(solid, resolution: resolution, quality: .preview)
            let gpuEnd = clock.now
            let onCPU = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: selection.evaluator))
                .meshReportingPath(solid, resolution: resolution, quality: .preview)
            let cpuEnd = clock.now
            #expect(onGPU.path == .gpu && onCPU.path == .cpu)
            guard round >= 2 else { continue }
            gpu.append(from: gpuStart, to: gpuEnd)
            cpu.append(from: gpuEnd, to: cpuEnd)
            triangles = (onGPU.mesh.triangleCount, onCPU.mesh.triangleCount)
        }
        print(gpu.line())
        print(cpu.line())
        print("BENCH i-1m triangles: GPU \(triangles.gpu), CPU \(triangles.cpu)")
    }

    #if canImport(CreatorOCCT)
    @Test func toImplicitOfTheBracket() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        let solid = try #require(solids(app, bracket.output).first)
        let clock = ContinuousClock()
        var samples = BenchSamples("i-3 To Implicit of the bracket (bake, OCCT)")
        for round in 0..<13 {
            let cache = ImplicitBakeCache()  // empty each time, so every round bakes
            let start = clock.now
            let baked = try await cache.baked(for: solid, tolerance: 0.01, kernel: app.kernel)
            guard round >= 3 else { continue }
            samples.append(from: start, to: clock.now)
            #expect(baked.blocks.storedBlockCount > 0)
        }
        print(samples.line(budget: Self.bakeBudget))
    }
    #endif

    @Test func exportingTheSheetAtATenthOfAMillimetre() async throws {
        guard Bench.requireRelease() else { return }
        let sheet = ImplicitBenchFixtures.sheet(exportResolution: 0.1)
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: sheet.graph), implicitEngine: .automatic)
        await app.settle()
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = ContinuousClock()
        let start = clock.now
        try await app.export(.stl, to: url)
        var samples = BenchSamples("i-4 export of the 100 mm sheet at 0.1 mm (STL, whole pipeline)")
        samples.append(from: start, to: clock.now)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 84, "the file has triangles")
        print(samples.line(budget: Self.exportBudget))
        let peak = ImplicitBenchFixtures.peakMemory
        let gigabytes = (Double(peak) / 1_000_000_000).formatted(.number.precision(.fractionLength(2)))
        let verdict = peak <= Self.memoryBudget ? "met" : "missed"
        print("BENCH i-4 peak memory \(gigabytes) GB (file \(size / 1_000_000) MB); budget 4.00 GB: \(verdict)")
    }
}

extension ImplicitBench {
    /// How many meshes the platform's Metal engine has made so far, or `nil` where there is none (the CPU engine records its numbers
    /// without a budget, D11).
    static func meshesMade() async -> Int? {
        #if canImport(Metal)
        return await MetalImplicitEngine.shared?.meshesMade
        #else
        return nil
        #endif
    }

    /// Rows i-1 and i-2 run the Mesh node, which falls back to the CPU mesher without a word (U4), and a CPU mesh of the sheet still
    /// meets i-1's second: so a row's run fails unless the engine made a mesh for each of its `rounds`.
    static func expectMeshedOnTheGPU(since before: Int?, atLeast rounds: Int, row: String) async {
        guard let before, let after = await meshesMade() else { return }
        #expect(after - before >= rounds, "BENCH \(row): \(after - before) of \(rounds) meshes were made on the GPU")
    }
}

/// The CPU mesher over a GPU engine's values: an evaluator that only evaluates, so `ImplicitMesher` does not ask it to mesh.
private struct SamplesOnlyEvaluator: ImplicitBatchEvaluator {
    let inner: any ImplicitBatchEvaluator

    var engineName: String { inner.engineName }

    func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await inner.evaluate(points)
    }
}
