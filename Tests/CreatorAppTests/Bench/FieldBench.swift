import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing
@testable import CreatorApp

/// Fields spec §7, rows 1 to 3 (row 4, the tinted preview, comes with the previews in 7b-3). Release, idle Mac; prints
/// `BENCH field-…` lines, with each row's budget judged on the median:
/// 1. a five-node field (a source, a remap, noise, a multiply, a clamp) over 10,000 points, no kernel distance: under 5 ms;
/// 2. the signed distance from a plate to 10,000 points on OCCT: under 100 ms the first time, about nothing cached (a plate is
///    planes and cylinders; 2b is the same points against a smooth loft, recorded and not gated);
/// 3. the fields spec puts Field Scatter's 2,000 points on a face here; Field Scatter arrives in 7b-3, so this row measures the
///    work it will start with at the same size and budget, Sample Field and then Cull by Field over a tree of 2,000
///    placements (50 ms). 7b-3 adds the Field Scatter row beside it.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct FieldBench {
    static let fiveNodeBudget = 5.0
    static let distanceBudget = 100.0
    static let placementsBudget = 50.0

    @Test func aFiveNodeFieldOverTenThousandPoints() async throws {
        guard Bench.requireRelease() else { return }
        let points = FieldBenchFixtures.points(10_000)
        let kernel = FakeKernel()
        let clock = ContinuousClock()
        var samples = BenchSamples("field-1 five nodes × 10,000 points (no kernel)")
        for round in 0..<65 {
            let start = clock.now
            let values = try await FieldSampler.sample(FieldBenchFixtures.fiveNodeField, at: points, kernel: kernel)
            guard round >= 5 else { continue }
            samples.append(from: start, to: clock.now)
            #expect(values.count == points.count)
        }
        print(samples.line(budget: Self.fiveNodeBudget))
    }

    @Test func theSignedDistanceToASolidOverTenThousandPoints() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        let plate = try await FieldBenchFixtures.plate(kernel)
        let field = Field.distance(.kernel(.solid(plate)), signed: true)
        let points = FieldBenchFixtures.points(10_000)
        let clock = ContinuousClock()
        var first = BenchSamples("field-2 signed distance to a plate × 10,000 points, first (OCCT)")
        var cached = BenchSamples("field-2 signed distance to a plate × 10,000 points, cached")
        for round in 0..<25 {
            let cache = FieldDistanceCache()  // a new cache each round, so the first sampling always asks the kernel
            let begin = clock.now
            let values = try await FieldSampler.sample(field, at: points, kernel: kernel, cache: cache)
            let middle = clock.now
            _ = try await FieldSampler.sample(field, at: points, kernel: kernel, cache: cache)
            let end = clock.now
            guard round >= 3 else { continue }
            first.append(from: begin, to: middle)
            cached.append(from: middle, to: end)
            #expect(values.count == points.count)
        }
        print(first.line(budget: Self.distanceBudget))
        print(cached.line())
    }

    /// Recorded, not gated (decision 13): the same 10,000 points against a smooth loft, which has B-spline faces.
    @Test func theSignedDistanceToALoftOverTenThousandPoints() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        let loft = try await FieldBenchFixtures.loft(kernel)
        let field = Field.distance(.kernel(.solid(loft)), signed: true)
        let points = FieldBenchFixtures.points(10_000)
        let clock = ContinuousClock()
        var first = BenchSamples("field-2b signed distance to a smooth loft × 10,000 points, first (OCCT)")
        for round in 0..<10 {
            let begin = clock.now
            let values = try await FieldSampler.sample(field, at: points, kernel: kernel, cache: FieldDistanceCache())
            guard round >= 2 else { continue }
            first.append(from: begin, to: clock.now)
            #expect(values.count == points.count)
        }
        print(first.line())
    }

    @Test func sampleFieldAndCullByFieldOverTwoThousandPlacements() async throws {
        guard Bench.requireRelease() else { return }
        let tree = FieldBenchFixtures.placements(rows: 40, columns: 50)
        let registry = BuiltInNodes.registry
        let sampleContext = EvalContext(node: registry.makeNode(SampleFieldNode.typeID), item: 0, parameters: [:])
        let cullContext = EvalContext(node: registry.makeNode(CullByFieldNode.typeID), item: 0, parameters: [:])
        let field = Scalar.field(FieldBenchFixtures.placementField)
        let sampleInputs = NodeInputs(item: 0, slots: ["field": .item(field), "at": .tree(tree)])
        let cullInputs = NodeInputs(item: 0, slots: [
            "placements": .tree(tree), "field": .item(field), "mode": .item(.integer(1)), "level": .item(.number(0.5)),
            "keep": .item(.integer(0)), "seed": .item(.integer(3)),
        ])
        let kernel = FakeKernel()
        let clock = ContinuousClock()
        var samples = BenchSamples("field-3 Sample Field + Cull by Field × 2,000 placements")
        for round in 0..<45 {
            let start = clock.now
            let sampled = try await SampleFieldNode.evaluate(sampleInputs, kernel: kernel, context: sampleContext)
            let culled = try await CullByFieldNode.evaluate(cullInputs, kernel: kernel, context: cullContext)
            guard round >= 5 else { continue }
            samples.append(from: start, to: clock.now)
            #expect(sampled.trees["values"]?.itemCount == 2000 && culled.trees["placements"] != nil)
        }
        print(samples.line(budget: Self.placementsBudget))
    }
}
