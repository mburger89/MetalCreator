import CreatorKernel
import Testing
@testable import CreatorApp

/// Patterns spec §7: "~200 instances, edit-to-preview within a second or two (release build, idle Mac)". A 210 × 110 × 6
/// plate with 200 Ø5 through-holes, three ways (`PatternBenchApp`): the Hole Pattern shortcut, the same with a Fillet on
/// one patterned hole, and Place with a Boolean. Each is built once (the cold evaluation: every node, the scene and its
/// meshes), then the holes' diameter is edited 40 times to a value never seen before (4.00 → 4.39 mm), each step waiting
/// for the evaluation, the scene and its meshes: the edit-to-preview of a person dragging the size. Prints
/// `BENCH pattern-…` lines, with the 2 s budget judged on the edit's median.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct PatternBench {
    @Test func theHoleShortcut() async throws {
        try await measure(.shortcut, "pattern-200 Hole Pattern")
    }

    @Test func theHoleShortcutWithAFilletOnOneHole() async throws {
        try await measure(.fillet, "pattern-200 Hole Pattern + Fillet on one hole")
    }

    @Test func placeAndBoolean() async throws {
        try await measure(.explicit, "pattern-200 Place + Boolean")
    }

    func measure(_ variant: PatternBenchApp.Variant, _ name: String) async throws {
        guard Bench.requireRelease() else { return }
        let clock = ContinuousClock()
        let started = clock.now
        let bench = try await PatternBenchApp(variant)
        var cold = BenchSamples("\(name) cold build (every node, scene and meshes)")
        cold.append(from: started, to: clock.now)
        expectAllOK(bench.app, "\(name), built")
        var edit = BenchSamples("\(name) edit diameter (evaluate+scene+meshes)")
        for step in 0..<40 {
            let begin = clock.now
            try await bench.setDiameter(4 + Double(step) * 0.01)
            edit.append(from: begin, to: clock.now)
        }
        expectAllOK(bench.app, "\(name), after the edits")
        print(cold.line())
        print(edit.line(budget: Bench.patternBudget))
    }
}
