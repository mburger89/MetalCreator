import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// The kernel items the M0–M1 carry-over note left for M7, measured on OCCT:
/// - `oriented()` runs `BRepLib::OrientClosedSolid` on every extrude, revolve and loft: its cost is bounded by each
///   whole operation's;
/// - `OCCTKernel` runs on the default actor executor: how long the main actor waits during a bracket re-evaluation;
/// - per-item calls take the process-wide lock and an actor hop each: what one costs, against an item's work.
/// Prints `BENCH kernel-…` lines.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct KernelBench {
    static func tag() -> NodeTag { NodeTag(node: NodeID(), item: 0) }

    @Test func eachSolidOperationBoundsOriented() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        var extrude = BenchSamples("kernel-extrude (60 × 40 × 6 plate)"), revolve = BenchSamples("kernel-revolve (tube)")
        var loft = BenchSamples("kernel-loft (two rectangles)")
        let clock = ContinuousClock()
        for step in 0..<60 {
            let a = clock.now
            _ = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: Self.tag())
            let b = clock.now
            _ = try await kernel.revolve(.rectangle(width: 10, height: 20, plane: .xz),
                                         axis: Axis(origin: Vector3(-20, 0, 0), direction: .unitZ), angle: .degrees(360),
                                         tag: Self.tag())
            let c = clock.now
            let sections: [Profile2D] = [
                .rectangle(width: 10, height: 20, plane: .xy),
                .rectangle(width: 20, height: 10, plane: Plane.xy.offset(by: 30)),
            ]
            _ = try await kernel.loft(sections, ruled: false, tag: Self.tag())
            let d = clock.now
            guard step >= 10 else { continue }
            extrude.append(from: a, to: b)
            revolve.append(from: b, to: c)
            loft.append(from: c, to: d)
        }
        print(extrude.line())
        print(revolve.line())
        print(loft.line())
    }

    @Test func aCallsHopAndLockCostAgainstItsWork() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        let clock = ContinuousClock()
        var lock = BenchSamples("kernel-lock (uncontended, per 100,000 calls)")
        for _ in 0..<50 {
            let start = clock.now
            for _ in 0..<100_000 { OCCTKernel.serialized {} }
            lock.append(from: start, to: clock.now)
        }
        var hop = BenchSamples("kernel-hop (refused calls: an actor round trip each, no OCCT; per 100 calls)")
        for _ in 0..<50 {
            let start = clock.now
            for _ in 0..<100 {
                _ = try? await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 0, mode: .oneSided,
                                              tag: Self.tag())
            }
            hop.append(from: start, to: clock.now)
        }
        print(lock.line())
        print(hop.line())
    }

    @Test func theMainActorStaysFreeWhileTheBracketReEvaluates() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        var wall = BenchSamples("kernel-bracket re-evaluation (Width 60 ↔ 90, wall)")
        var gaps = BenchSamples("kernel-main-actor gap during re-evaluation")
        let clock = ContinuousClock()
        for (index, width) in [90.0, 60, 90, 60, 90, 60, 90, 60].enumerated() {
            try app.document.perform(.setParameter(bracket.width.id, .number(width + Double(index) * 0.5)))
            let start = clock.now
            var last = start
            while app.document.isEvaluating {
                await Task.yield()
                let now = clock.now
                gaps.append(from: last, to: now)
                last = now
            }
            wall.append(from: start, to: clock.now)
        }
        await app.settle()
        expectAllOK(app, "after re-evaluating")
        print(wall.line())
        print(gaps.line(budget: Bench.frameBudget))
    }
}
