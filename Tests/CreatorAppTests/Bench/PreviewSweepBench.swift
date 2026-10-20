#if canImport(Metal)
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Errata D15: how many preview triangles MetalCreator shows smoothly, to set `PreviewSchedule.maximumTriangles` from a measurement.
/// A sheet of 8 mm cells (`PreviewSweepFixtures`) is meshed at a ladder of voxel sizes making about 0.25M to 8M triangles, and at each
/// rung the run records the first-pass meshing time on the GPU mesher and on the CPU mesher (median of 3), the orbit's frame cost with
/// the mesh in the viewport (as `OrbitBench`: model step, window CPU and GPU per frame, median and p95 over 60 steps after 10 warm-up
/// frames; panel shown and hidden), the memory and the triangle count, then prints the cap `PreviewSweepRule` picks.
/// Release, idle Mac: `scripts/preview-sweep.sh`. Prints `BENCH preview-sweep …`.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/preview-sweep.sh)"))
struct PreviewSweepBench {
    static let warmUp = 10
    static let orbitSteps = 70
    static let meshRounds = 3

    @Test func theLadderOfPreviewMeshes() async throws {
        guard Bench.requireRelease() else { return }
        let sheet = PreviewSweepFixtures.sheet()
        let solid = try await PreviewSweepFixtures.solid(of: sheet)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic)
        guard selection.evaluator.engineName != "CPU" else {
            print("BENCH preview-sweep skipped: this machine has no GPU engine")
            return
        }
        // The first mesh of the process compiles the shaders; the sweep times none of that.
        _ = try await ImplicitMesher(evaluator: selection.evaluator)
            .mesh(solid, resolution: PreviewSweepFixtures.ladder[0].resolution, quality: .preview)
        var rungs: [PreviewSweepRung] = []
        for (number, step) in PreviewSweepFixtures.ladder.enumerated() {
            let label = "rung \(number + 1) (\(step.name))"
            let meshed = try await Self.meshTimes(solid, evaluator: selection.evaluator, resolution: step.resolution, label: label)
            let shown = try await Self.inViewport(sheet, resolution: step.resolution, label: label)
            let rung = PreviewSweepRung(
                resolution: step.resolution, triangles: shown.triangles, gpuMeshMilliseconds: meshed.gpu, cpuMeshMilliseconds: meshed.cpu,
                panelShown: shown.panelShown, panelHidden: shown.panelHidden, addedFootprint: shown.addedFootprint)
            rungs.append(rung)
            // What the rung's app, renderer and meshes left behind: the next rung's footprint starts from it.
            await Task.yield()
            // malloc returns freed blocks on a timer of about 10 s (measured), so the teardown reading waits longer than that.
            let settled = await PreviewSweepFixtures.settledFootprint(interval: .seconds(1), stableReadings: 14, limit: 45)
            print("BENCH preview-sweep \(label) teardown: \(shown.watch.describe()); Metal allocated "
                + "\(Self.megabytes(PreviewSweepRelease.metalAllocated)); footprint \(Self.megabytes(settled.immediate)) at once, "
                + "\(Self.megabytes(settled.settled)) settled after \(Self.milliseconds(settled.seconds)) s; live malloc heap "
                + "\(Self.megabytes(settled.heapInUse))")
            let verdict = PreviewSweepRule.verdict(of: rung, smallest: rungs[0])
            print("BENCH preview-sweep \(label) rule: \(Self.describe(verdict, rung: rung, smallest: rungs[0]))")
        }
        Self.summarise(rungs)
    }

    // MARK: Meshing

    /// The medians of `meshRounds` first passes at `resolution`, in milliseconds, on the GPU mesher and on the CPU mesher over the
    /// GPU's values (as row i-1m), and the mesh's own bytes. The meshes are gone when this returns, so they don't count in the footprint.
    private static func meshTimes(_ solid: ImplicitSolid, evaluator: any ImplicitBatchEvaluator, resolution: Double, label: String)
        async throws -> (gpu: Double, cpu: Double) {
        let clock = ContinuousClock()
        var gpu = BenchSamples("preview-sweep \(label) mesh-gpu"), cpu = BenchSamples("preview-sweep \(label) mesh-cpu")
        var made: TriangleMesh?
        for _ in 0..<meshRounds {
            let gpuStart = clock.now
            let onGPU = try await ImplicitMesher(evaluator: evaluator).meshReportingPath(solid, resolution: resolution, quality: .preview)
            let gpuEnd = clock.now
            let onCPU = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: evaluator))
                .meshReportingPath(solid, resolution: resolution, quality: .preview)
            let cpuEnd = clock.now
            #expect(onGPU.path == .gpu && onCPU.path == .cpu, "BENCH preview-sweep \(label): the GPU mesh fell back to the CPU")
            gpu.append(from: gpuStart, to: gpuEnd)
            cpu.append(from: gpuEnd, to: cpuEnd)
            made = onGPU.mesh
        }
        if let made {
            let vertexBytes = MemoryLayout<SIMD3<Float>>.stride
            let positions = made.positions.count * vertexBytes, normals = made.normals.count * vertexBytes
            let indices = made.triangles.count * MemoryLayout<UInt32>.stride
            print("BENCH preview-sweep \(label) mesh: res \(resolution.formatted(.number.precision(.fractionLength(0...3)))) mm, "
                + "\(made.triangleCount) triangles, \(made.vertexCount) vertices; own bytes \(megabytes(positions + normals + indices)) "
                + "(positions \(megabytes(positions)), normals \(megabytes(normals)), indices \(megabytes(indices)))")
        }
        print(gpu.line())
        print(cpu.line())
        return (gpu.median, cpu.median)
    }

    // MARK: Viewport

    /// What the app showing the mesh at `resolution` measured.
    private struct Shown {
        var watch: PreviewSweepRelease
        var triangles: Int
        var panelShown: PreviewSweepRung.Orbit
        var panelHidden: PreviewSweepRung.Orbit
        var addedFootprint: Int
    }

    /// The sheet previewed down to `resolution` in the app (its own meshing and refinement), orbited with the panel docked left and
    /// hidden. The footprint is read after the first frame has drawn, so the GPU's copy of the mesh is in it, and is compared with the
    /// footprint of the same renderer after it has drawn an empty app's frame (its pipelines, atlas and textures are made by then), so
    /// the difference is the mesh, its refinement, its display copy and its GPU copy, and the app that holds them.
    private static func inViewport(_ sheet: PreviewSweepFixtures.Sheet, resolution: Double, label: String) async throws -> Shown {
        let renderer = try BenchRenderer()
        let empty = AppModel(kernel: FakeKernel())
        await empty.settle()
        renderer.place(empty)
        let emptyInput = AppInput(model: empty)
        try renderer.drawViewport(empty.viewport)
        try renderer.composite(renderer.windowScene(empty, input: emptyInput))
        let before = await PreviewSweepFixtures.settledFootprint().settled
        let graph = PreviewSweepFixtures.previewing(sheet.graph, at: resolution)
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph), implicitEngine: .automatic)
        await app.settle()
        await app.meshRefinement.waitForRefinement()
        await app.settle()
        await app.viewport.waitForMeshes()
        let triangles = try #require(app.viewport.items.first?.solid.displayedMesh).indices.count / 3
        let watch = PreviewSweepRelease(app: app, renderer: renderer, solids: app.viewport.items.map(\.solid))
        renderer.place(app)
        let input = AppInput(model: app)
        // The first frame uploads the mesh to the GPU.
        try renderer.drawViewport(app.viewport)
        let after = await PreviewSweepFixtures.settledFootprint().settled
        let added = max(0, after - before)
        let gpuBuffer = 3 * triangles * MemoryLayout<MeshVertex>.stride
        print("BENCH preview-sweep \(label) memory: footprint \(megabytes(before)) with an empty app drawn, "
            + "\(megabytes(after)) with the mesh in the viewport, added \(megabytes(added)); "
            + "GPU vertex buffer \(megabytes(gpuBuffer)) (de-indexed, derived from the layout)")
        print("BENCH preview-sweep \(label) viewport: \(triangles) triangles shown")
        app.editor.setDock(.left)
        await app.settle()
        let shown = try await orbit(app, renderer: renderer, input: input, name: "preview-sweep \(label) panel-left")
        app.editor.setDock(.hidden)
        await app.settle()
        let hidden = try await orbit(app, renderer: renderer, input: input, name: "preview-sweep \(label) panel-hidden")
        return Shown(watch: watch, triangles: triangles, panelShown: shown, panelHidden: hidden, addedFootprint: added)
    }

    /// Orbits as `OrbitBench` does (a right-drag of small steps; each frame is the step, the window's frame and both GPU passes) and
    /// prints the model, window CPU and GPU lines.
    private static func orbit(_ app: AppModel, renderer: BenchRenderer, input: AppInput, name: String) async throws
        -> PreviewSweepRung.Orbit {
        var model = BenchSamples("\(name) model"), cpu = BenchSamples("\(name) window-cpu")
        var gpu = BenchSamples("\(name) gpu (viewport + window)")
        let clock = ContinuousClock()
        let start = ScreenPoint(900, 450)
        for step in 0..<orbitSteps {
            let begin = clock.now
            app.viewport.dragChanged(from: start, to: ScreenPoint(900 + Double(step) * 4, 450 + Double(step)), modifiers: [],
                                     button: .secondary)
            await app.settle()
            let stepped = clock.now
            let scene = renderer.windowScene(app, input: input)
            let built = clock.now
            try renderer.drawViewport(app.viewport)
            try renderer.composite(scene)
            let drawn = clock.now
            guard step >= warmUp else { continue }
            model.append(from: begin, to: stepped)
            cpu.append(from: stepped, to: built)
            gpu.append(from: built, to: drawn)
        }
        app.viewport.dragEnded(from: start, at: ScreenPoint(1340, 560), modifiers: [], button: .secondary)
        print(model.line())
        print(cpu.line(budget: Bench.frameBudget))
        print(gpu.line(budget: Bench.frameBudget))
        return PreviewSweepRung.Orbit(cpuP95: cpu.percentile95, gpuP95: gpu.percentile95)
    }

    // MARK: Reporting

    private static func megabytes(_ bytes: Int) -> String {
        (Double(bytes) / 1_000_000).formatted(.number.precision(.fractionLength(0)).grouping(.never)) + " MB"
    }

    private static func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never))
    }

    /// The four tests of the rule with their values, and the verdict.
    private static func describe(_ verdict: PreviewSweepRule.Verdict, rung: PreviewSweepRung, smallest: PreviewSweepRung) -> String {
        func mark(_ passed: Bool) -> String { passed ? "met" : "missed" }
        let shownExtra = rung.panelShown.cpuP95 - smallest.panelShown.cpuP95
        let hiddenExtra = rung.panelHidden.cpuP95 - smallest.panelHidden.cpuP95
        return "(a) gpu p95 \(milliseconds(rung.panelShown.gpuP95)) shown / \(milliseconds(rung.panelHidden.gpuP95)) hidden ms "
            + "(<= \(milliseconds(PreviewSweepRule.gpuP95Budget))): \(mark(verdict.gpuFrame)); "
            + "(b) window cpu p95 \(milliseconds(shownExtra)) / \(milliseconds(hiddenExtra)) ms over the smallest rung "
            + "(<= \(milliseconds(PreviewSweepRule.cpuP95Slack))): \(mark(verdict.cpuFrame)); "
            + "(c) footprint added \(megabytes(rung.addedFootprint)) (<= \(megabytes(PreviewSweepRule.footprintBudget))): "
            + "\(mark(verdict.footprint)); "
            + "(d) gpu mesh \(milliseconds(rung.gpuMeshMilliseconds)) ms (<= \(milliseconds(PreviewSweepRule.meshBudget))): "
            + "\(mark(verdict.meshing)) => \(verdict.passes ? "PASS" : "FAIL")"
    }

    /// One row per rung, then the cap the rule picks.
    private static func summarise(_ rungs: [PreviewSweepRung]) {
        for rung in rungs {
            print("BENCH preview-sweep row: \(rung.triangles) triangles at \(milliseconds(rung.resolution)) mm; "
                + "mesh gpu \(milliseconds(rung.gpuMeshMilliseconds)) ms, cpu \(milliseconds(rung.cpuMeshMilliseconds)) ms; "
                + "orbit gpu p95 \(milliseconds(rung.panelShown.gpuP95)) ms shown, \(milliseconds(rung.panelHidden.gpuP95)) ms hidden; "
                + "window cpu p95 \(milliseconds(rung.panelShown.cpuP95)) ms shown, \(milliseconds(rung.panelHidden.cpuP95)) ms hidden; "
                + "footprint added \(megabytes(rung.addedFootprint))")
        }
        let peak = (Double(ImplicitBenchFixtures.peakMemory) / 1_000_000_000).formatted(.number.precision(.fractionLength(2)))
        print("BENCH preview-sweep process peak resident \(peak) GB")
        if let cap = PreviewSweepRule.capCandidate(rungs) {
            print("BENCH preview-sweep cap-candidate \(cap.triangles)")
        } else {
            print("BENCH preview-sweep cap-candidate none (the smallest rung misses the rule)")
        }
    }
}
#endif
