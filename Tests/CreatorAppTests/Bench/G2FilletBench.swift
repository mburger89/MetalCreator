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
            // A typed edit, not a handle drag: a drag previews G2 at G1 (`isScrubbing`), and this row measures the G2 build.
            var samples = BenchSamples("g2-fillet-1 bracket fillets \(name), edit to preview")
            let clock = ContinuousClock()
            for step in 0..<40 {
                let begin = clock.now
                try app.document.perform(.setInput(bracket.fillet.id, "radius", .number(2 + Double(step) * 0.02)))
                await app.settle()
                if step >= 5 { samples.append(from: begin, to: clock.now) }
            }
            expectAllOK(app, "after the \(name) edits")
            print(samples.line())
        }
    }

    /// Row `g2-fillet-drag`: a drag of a G2 fillet's radius handle. The steps are previewed at G1 (`DocumentModel.isScrubbing`);
    /// the release builds the G2 surface once.
    @Test func aG2DragPreviewsAtG1AndReleasesAtG2() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        try app.document.perform(.setInput(bracket.fillet.id, "continuity", .integer(1)))
        app.editor.selection = [bracket.fillet.id]
        await app.settle()
        expectAllOK(app, "the bracket at G2")
        let handle = try #require(app.viewport.handles.first, "the selected Fillet shows its radius handle")
        var steps = BenchSamples("g2-fillet-drag G2 fillet, drag step (G1 preview), edit to preview")
        let clock = ContinuousClock()
        for step in 0..<40 {
            let begin = clock.now
            app.handleChanged(handle.id, 2 + Double(step) * 0.02, .changed)
            await app.settle()
            if step >= 5 { steps.append(from: begin, to: clock.now) }
        }
        var release = BenchSamples("g2-fillet-drag G2 fillet, release (G2 built), edit to preview")
        let begin = clock.now
        app.handleChanged(handle.id, 2.8, .ended)
        await app.settle()
        release.append(from: begin, to: clock.now)
        expectAllOK(app, "after the drag")
        print(steps.line())
        print(release.line())
    }
}
#endif
