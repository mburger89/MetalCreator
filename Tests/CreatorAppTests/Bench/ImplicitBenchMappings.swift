// Test fixture file: the graphs of the conformal-mapping benchmarks (implicit spec §3.5, §6; plan 7c-4), checked in the default run.
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

extension ImplicitBenchFixtures {
    /// A gyroid sheet wrapped round the axis of an Implicit Cylinder (row i-9): the Cylindrical mapping about the world Z axis, which runs
    /// through the middle of the part, so the exclusion and the stretch of the mapping (about the mean radius over the exclusion) are in
    /// the lipschitz bound, as they are in a real wrapped part.
    static func cylindricalSheet(radius: Double = 45, height: Double = 100, cell: Double = 10, wall: Double = 1.5,
                                 exportResolution: Double = 0.2) -> Sheet {
        var builder = GraphBuilder()
        let post = builder.add(ImplicitCylinderNode.self, ["radius": .number(radius), "height": .number(height)])
        let gyroid = builder.add(TPMSNode.self, ["cell size": .number(cell), "thickness": .number(wall), "mapping": .integer(1)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(exportResolution)])
        let output = builder.add(OutputNode.self)
        builder.wire(post, "implicit", to: gyroid, "region")
        builder.wire(gyroid, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return Sheet(graph: builder.graph, thickness: gyroid, output: output)
    }

    #if canImport(CreatorOCCT)
    /// A gyroid sheet whose cells follow the side of an OpenCascade cylinder (row i-10): a circle extruded, To Implicit, and the TPMS
    /// node set to Face mapping on the cylinder's side, picked from the solid the kernel made. The kernel is the one the rows measure with.
    static func faceSheet(kernel: any Kernel, diameter: Double = 90, height: Double = 100, cell: Double = 10, wall: Double = 1.5,
                          exportResolution: Double = 0.2) async throws -> Sheet {
        var builder = GraphBuilder()
        let circle = builder.add(CircleNode.self, ["diameter": .number(diameter)])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(height)])
        let implicit = builder.add(ToImplicitNode.self)
        let gyroid = builder.add(TPMSNode.self, ["cell size": .number(cell), "thickness": .number(wall), "mapping": .integer(3)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(exportResolution)])
        let output = builder.add(OutputNode.self)
        builder.wire(circle, "profile", to: extrude, "profile")
        builder.wire(extrude, "solid", to: implicit, "solid")
        builder.wire(implicit, "implicit", to: gyroid, "region")
        builder.wire(gyroid, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: kernel).evaluate(builder.graph, demand: [extrude.id])
        guard case .solid(let part)? = report.results[extrude.id]?.outputs?["solid"]?.items.first,
              let side = part.topology.faces.first(where: { $0.kind == .cylinder }), let pick = part.topology.facePick(for: side.id) else {
            throw BenchFixtureError.noSolid(String(describing: report.results[extrude.id]?.state))
        }
        builder.graph.nodes[gyroid.id]?.inputValues[NodeSetting.face] = .facePick(pick)
        return Sheet(graph: builder.graph, thickness: gyroid, output: output)
    }
    #endif
}

extension ImplicitBench {
    /// Proposed budgets (plan 7c-4, user decision U9): a wrapped lattice's first pass is held to the straight sheet's second, its edit to
    /// 250 ms (the chart's lookups and the larger lipschitz bound cost more than i-2's 100 ms), the first evaluation (the chart's own 5 s, To Implicit and the first pass) to 10 s.
    static let cylindricalBudget = 1000.0
    static let faceEditBudget = 250.0
    static let chartBudget = 10000.0

    @Test func theFirstPreviewPassOfACylindricallyMappedLattice() async throws {
        guard Bench.requireRelease() else { return }
        let sheet = ImplicitBenchFixtures.cylindricalSheet()
        let clock = ContinuousClock()
        var warm = BenchSamples("i-9 first preview pass of a gyroid wrapped round a 90 mm post (Cylindrical)")
        let madeBefore = await Self.meshesMade()
        for round in 0..<8 {
            let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel(), implicitEngine: .automatic)
            let start = clock.now
            let report = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id])
            if round >= 2 { warm.append(from: start, to: clock.now) }
            #expect(report.results[sheet.output.id]?.state.isSuccess == true)
        }
        print(warm.line(budget: Self.cylindricalBudget))
        await Self.expectMeshedOnTheGPU(since: madeBefore, atLeast: 8, row: "i-9")
    }

    #if canImport(CreatorOCCT)
    @Test func measuringAFaceAndEditingAFaceMappedLattice() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        let sheet = try await ImplicitBenchFixtures.faceSheet(kernel: kernel)
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel, implicitEngine: .automatic)
        let clock = ContinuousClock()
        // i-10c: the first evaluation bakes the solid and measures the face (a chart per solid object, so a fresh one is cold).
        var cold = BenchSamples("i-10c first evaluation of a Face-mapped lattice (To Implicit and the face's chart, OCCT)")
        let start = clock.now
        let first = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id])
        cold.append(from: start, to: clock.now)
        #expect(first.results[sheet.output.id]?.state.isSuccess == true)
        print(cold.line(budget: Self.chartBudget))
        // i-10: a thickness edit on the warm evaluator: the chart is cached, so it is one coarse pass.
        let madeBefore = await Self.meshesMade()
        var samples = BenchSamples("i-10 thickness edit of a Face-mapped lattice (one coarse pass, chart cached)")
        var graph = sheet.graph
        for round in 0..<13 {
            let wall = ImplicitBenchFixtures.thickness / 2 + 0.01 * Double(round + 1)
            graph.nodes[sheet.thickness.id]?.inputValues["thickness"] = .number(wall)
            let editStart = clock.now
            let report = try await evaluator.evaluate(graph, demand: [sheet.output.id])
            guard round >= 3 else { continue }
            samples.append(from: editStart, to: clock.now)
            #expect(report.results[sheet.output.id]?.state.isSuccess == true)
        }
        print(samples.line(budget: Self.faceEditBudget))
        await Self.expectMeshedOnTheGPU(since: madeBefore, atLeast: 13, row: "i-10")
    }
    #endif
}
