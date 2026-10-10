import Testing
@testable import CreatorApp

/// Spec §7.3: "While the fillet radius is being dragged on the bracket, the viewport updates within 100 ms of each
/// value change. Measured from command to presented frame, as the median over a scripted drag." The §7.2 bracket on
/// OCCT with its Fillet selected; each step drags the radius handle to a new value (2.00 → 3.48 mm in 0.02 mm steps,
/// never a value the evaluator has cached; the bracket's edges take up to about 4 mm), then waits for the evaluation,
/// the scene and its meshes, then draws the window's frame (CPU) and both GPU passes. Prints `BENCH fillet-drag …`.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct FilletDragBench {
    @Test func draggingTheFilletRadius() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        app.editor.selection = [bracket.fillet.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first, "the selected Fillet shows its radius handle")
        let input = AppInput(model: app)
        let renderer = try BenchRenderer()
        renderer.place(app)
        var evaluate = BenchSamples("fillet-drag evaluate+mesh"), cpu = BenchSamples("fillet-drag window-cpu")
        var gpu = BenchSamples("fillet-drag gpu (viewport + window)"), total = BenchSamples("fillet-drag command-to-frame")
        var shown = 0
        let clock = ContinuousClock()
        for step in 0..<75 {
            let generation = app.viewport.sceneGeneration
            let begin = clock.now
            app.handleChanged(handle.id, 2 + Double(step) * 0.02, .changed)
            await app.settle()
            let evaluated = clock.now
            let scene = renderer.windowScene(app, input: input)
            let built = clock.now
            try renderer.drawViewport(app.viewport)
            try renderer.composite(scene)
            let drawn = clock.now
            if app.viewport.sceneGeneration > generation { shown += 1 }
            evaluate.append(from: begin, to: evaluated)
            cpu.append(from: evaluated, to: built)
            gpu.append(from: built, to: drawn)
            total.append(from: begin, to: drawn)
        }
        app.handleChanged(handle.id, 3.48, .ended)
        await app.settle()
        expectAllOK(app, "after the drag")
        #expect(shown == 75, "every step showed a new part")
        print("BENCH fillet-drag: \(shown) of 75 steps showed a new part")
        print(evaluate.line())
        print(cpu.line())
        print(gpu.line())
        print(total.line(budget: Bench.dragBudget))
    }
}
