#if canImport(Metal) && canImport(CreatorOCCT)
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Row `g2-fillet-1`: the §7.2 bracket's Fillet at Tangent (G1) against Curvature (G2). Each step edits the radius to a
/// value the evaluator has not cached (2.00 to 3.48 mm in 0.02 mm steps, as `FilletDragBench`), then waits for the
/// evaluation, the scene and its meshes: edit to preview. Release; prints `BENCH g2-fillet-1 …`. Recorded, not gated.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct G2FilletBench {
    @Test func theBracketsFilletsAtBothContinuities() async throws {
        guard Bench.requireRelease() else { return }
        for (name, continuity) in [("G1", 0), ("G2", 1)] {
            let (app, bracket) = try await makeBracketBenchApp()
            try app.document.perform(.setInput(bracket.fillet.id, "continuity", .integer(continuity)))
            app.editor.selection = [bracket.fillet.id]
            await app.settle()
            expectAllOK(app, "the bracket at \(name)")
            let handle = try #require(app.viewport.handles.first, "the selected Fillet shows its radius handle")
            var samples = BenchSamples("g2-fillet-1 bracket fillets \(name), edit to preview")
            let clock = ContinuousClock()
            for step in 0..<40 {
                let begin = clock.now
                app.handleChanged(handle.id, 2 + Double(step) * 0.02, .changed)
                await app.settle()
                if step >= 5 { samples.append(from: begin, to: clock.now) }
            }
            app.handleChanged(handle.id, 3.48, .ended)
            await app.settle()
            expectAllOK(app, "after the \(name) edits")
            print(samples.line())
        }
    }
}
#endif
