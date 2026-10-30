#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing
@testable import CreatorApp

/// Section analysis part B (section spec §3.4), the cap's three rows. Release, idle Mac; prints `BENCH sa-…` lines, with the
/// 60 FPS frame (16.67 ms) as the budget each is judged against on the median. Recorded, not gated (spec §9).
/// 1. the bracket's part sectioned by `Kernel.section` on OCCT at 60 planes spread across its height;
/// 2. the gyroid sheet's preview mesh sliced by `MeshSlicer.slice` (which includes the cap's triangulation) at 60 planes;
/// 3. a drag on the bracket through `AppModel`: `setSectionOffset` then `settle()`, 60 steps, to the finished cap.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct SectionBench {
    static let budget = 16.67
    static let steps = 60
    static let stride = 0.25

    @Test func theBracketSectionPerDragStep() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        let solid = try #require(app.viewport.items.first { !$0.isGuide }?.solid)
        let bounds = try #require(app.viewport.sceneBounds)
        let tolerance = app.viewport.displayTolerance
        let kernel = app.kernel
        let clock = ContinuousClock()
        var samples = BenchSamples("sa-1 bracket section per drag step")
        var regions = 0
        for round in 0..<(Self.steps + 5) {
            let low = bounds.min.z + 0.5
            let z = low + (bounds.max.z - 0.5 - low) * Double(round) / Double(Self.steps + 4)
            let plane = Plane(origin: Vector3(0, 0, z), normal: Vector3(0, 0, 1), xAxis: Vector3(1, 0, 0))
            let start = clock.now
            let section = try await kernel.section(solid, by: plane, tolerance: tolerance)
            guard round >= 5 else { continue }
            samples.append(from: start, to: clock.now)
            regions = max(regions, section.regions.count)
        }
        #expect(regions > 0)
        print(samples.line(budget: Self.budget))
        print("BENCH sa-1 largest region count \(regions)")
    }

    @Test func theLatticeSlicePerDragStep() async throws {
        try await latticeSlice(row: "sa-2 lattice slice per drag step", skin: 0)
    }

    /// The same sheet inside a 1 mm skin: the cut is a frame with a hole for every closed pocket of the gyroid, more holes than sa-2.
    @Test func theSkinnedLatticeSlicePerDragStep() async throws {
        try await latticeSlice(row: "sa-2b skinned lattice slice per drag step", skin: 1)
    }

    func latticeSlice(row: String, skin: Double) async throws {
        guard Bench.requireRelease() else { return }
        let sheet = ImplicitBenchFixtures.sheet(skin: skin)
        let solid = try await ImplicitBenchFixtures.solid(of: sheet)
        let resolution = PreviewSchedule(.automatic).firstResolution(for: solid.bounds)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic)
        let mesh = try await ImplicitMesher(evaluator: selection.evaluator).mesh(solid, resolution: resolution, quality: .preview)
        let display = mesh.displayMesh
        let middle = (solid.bounds.min.z + solid.bounds.max.z) / 2
        let clock = ContinuousClock()
        var samples = BenchSamples(row)
        var shape = (regions: 0, holes: 0, triangles: 0)
        for round in 0..<(Self.steps + 5) {
            let z = middle + Double(round) * Self.stride
            let plane = Plane(origin: Vector3(0, 0, z), normal: Vector3(0, 0, 1), xAxis: Vector3(1, 0, 0))
            let start = clock.now
            let section = MeshSlicer.slice(positions: display.positions, triangles: display.indices, plane: plane)
            guard round >= 5 else { continue }
            samples.append(from: start, to: clock.now)
            let holes = section.regions.reduce(0) { $0 + max(0, $1.boundary.count - 1) }
            if holes >= shape.holes {
                shape = (section.regions.count, holes, section.regions.reduce(0) { $0 + $1.triangles.count / 3 })
            }
        }
        print(samples.line(budget: Self.budget))
        print("BENCH \(row.prefix(while: { $0 != " " })) mesh \(mesh.triangleCount) triangles at \(resolution) mm; richest slice: "
              + "\(shape.regions) regions, \(shape.holes) boundary loops beyond the first per region, \(shape.triangles) cap triangles")
    }

    @Test func theDragToACapOnTheBracket() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.setSection(true)
        await app.settle()
        let base = try #require(app.document.section).offset
        let clock = ContinuousClock()
        var samples = BenchSamples("sa-3 drag to cap on the bracket")
        for step in 0..<(Self.steps + 5) {
            let start = clock.now
            app.setSectionOffset(base + Double(step) * Self.stride)
            await app.settle()
            guard step >= 5 else { continue }
            samples.append(from: start, to: clock.now)
        }
        #expect(app.viewport.section != nil)
        print(samples.line(budget: Self.budget))
    }
}
#endif
