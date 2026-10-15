import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// Implicit spec §6, rows i-1 to i-6. Release, idle Mac, `scripts/bench.sh ImplicitBench`; each prints
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
/// - i-4: the export of i-1 at 0.1 mm to an STL, the whole pipeline: under 60 s and a peak memory under 4 GB. The export streams
///   (Errata D12): the bricks are meshed a window at a time into the file, so the memory is a window and the plan, not the mesh.
/// - i-4b: the same export to a 3MF: the file's size, the model XML's size and the time are recorded, with no budget (the XML is a few
///   times the STL, and deflate is the Mac's alone). Past 4 GB of XML the zip is Zip64 (`i-4z` below).
/// - i-4z: a zip entry of 4.7 GB written through `ZipWriter` and read by the system's `unzip -t`: the Zip64 path of D12's 150-million-triangle
///   3MF, which no unit test can afford. Recorded, no budget; a failure of `unzip` is a miss.
/// - i-5: Decimate of a 2,097,152-triangle sphere (a 100 mm ball, tolerance 0.01 mm), `MeshDecimator` alone: under 10 s.
/// - i-6: Mesh to Solid of a 100,000-triangle mesh on OCCT (the welding, the sewing, the merge and the check): under 15 s.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct ImplicitBench {
    static let firstPassBudget = 1000.0
    static let editBudget = 100.0
    static let bakeBudget = 500.0
    static let exportBudget = 60_000.0
    static let memoryBudget = 4_000_000_000
    static let decimateBudget = 10_000.0
    static let solidBudget = 15_000.0

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

    @Test func exportingTheSheetAsA3MFAtATenthOfAMillimetre() async throws {
        guard Bench.requireRelease() else { return }
        let sheet = ImplicitBenchFixtures.sheet(exportResolution: 0.1)
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: sheet.graph), implicitEngine: .automatic)
        await app.settle()
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = ContinuousClock()
        let start = clock.now
        try await app.export(.threeMF, to: url)
        var samples = BenchSamples("i-4b export of the 100 mm sheet at 0.1 mm (3MF, whole pipeline)")
        samples.append(from: start, to: clock.now)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let model = try #require(try ZipReader.listing(of: url).first { $0.name == "3D/3dmodel.model" })
        print(samples.line())
        let gigabytes = (Double(ImplicitBenchFixtures.peakMemory) / 1_000_000_000).formatted(.number.precision(.fractionLength(2)))
        print("BENCH i-4b 3MF file \(size / 1_000_000) MB, model XML \(model.size / 1_000_000) MB; "
            + "peak memory of the process so far \(gigabytes) GB")
        #expect(size > 1_000 && model.size > size / 100)
    }

    #if os(macOS)
    @Test func aZipEntryPastFourGigabytesIsValidZip64() throws {
        guard Bench.requireRelease() else { return }
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let line = Array("<triangle v1=\"1234567\" v2=\"1234568\" v3=\"1234569\"/>\n".utf8)
        let chunk = [[UInt8]](repeating: line, count: 20_000).flatMap { $0 }
        let chunks = 4_700
        let clock = ContinuousClock()
        let start = clock.now
        var zip = try ZipWriter(destination: url)
        try zip.beginEntry("3D/3dmodel.model")
        for _ in 0..<chunks { try zip.write(chunk) }
        try zip.endEntry()
        try zip.finish()
        var samples = BenchSamples("i-4z a \(chunk.count * chunks / 1_000_000) MB zip entry (\(ZipWriter.defaultMethod))")
        samples.append(from: start, to: clock.now)
        print(samples.line())
        let entry = try #require(try ZipReader.listing(of: url).first)
        #expect(entry.size == chunk.count * chunks && entry.size > 0xFFFF_FFFF, "the size is read from the Zip64 extra")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let said = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("BENCH i-4z unzip -t: exit \(process.terminationStatus) \(said.trimmingCharacters(in: .whitespacesAndNewlines))")
        #expect(process.terminationStatus == 0, "\(said)")
    }
    #endif

    @Test func decimatingTwoMillionTriangles() throws {
        guard Bench.requireRelease() else { return }
        let sphere = ImplicitBenchMeshes.sphere(subdivisions: 9, radius: 50)
        let clock = ContinuousClock()
        var samples = BenchSamples("i-5 decimate a \(sphere.triangleCount.formatted(.number.grouping(.never))) triangle sphere (0.01 mm)")
        var after = 0
        for round in 0..<4 {
            let start = clock.now
            let output = try MeshDecimator.decimate(positions: sphere.positions, triangles: sphere.triangles, tolerance: 0.01)
            let end = clock.now
            if round >= 1 { samples.append(from: start, to: end) }
            after = output.triangles.count / 3
        }
        print(samples.line(budget: Self.decimateBudget))
        print("BENCH i-5 triangles \(sphere.triangleCount) to \(after)")
        #expect(after < sphere.triangleCount)
    }

    #if canImport(CreatorOCCT)
    @Test func meshToSolidOfAHundredThousandTriangles() async throws {
        guard Bench.requireRelease() else { return }
        let ball = ImplicitBenchMeshes.uvSphere(segments: 400, rings: 126)
        let kernel = OCCTKernel()
        let clock = ContinuousClock()
        var samples = BenchSamples("i-6 Mesh to Solid of a \(ball.triangleCount.formatted(.number.grouping(.never))) triangle mesh (OCCT)")
        var faces = 0
        for round in 0..<3 {
            let start = clock.now
            let welded = MeshWelder.weld(positions: ball.positions, triangles: ball.triangles)
            let solid = try await kernel.meshToSolid(positions: welded.positions, triangles: welded.triangles,
                                                     tag: NodeTag(node: NodeID(), item: 0))
            let end = clock.now
            if round >= 1 { samples.append(from: start, to: end) }
            faces = solid.topology.faces.count
        }
        print(samples.line(budget: Self.solidBudget))
        print("BENCH i-6 faces \(faces)")
        #expect(faces > 0)
    }
    #endif
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
