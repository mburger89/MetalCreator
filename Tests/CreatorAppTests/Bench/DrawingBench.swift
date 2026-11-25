#if canImport(CreatorOCCT)
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import Testing
@testable import CreatorApp

/// Drawings spec benchmarks, release, idle Mac; prints `BENCH drawing-1 …` and `BENCH drawing-2-warm …` lines. Recorded, not gated.
/// drawing-1: the bracket's four projections (Front, Right, Top, Isometric) from the edit that adds them to the last landing, cache
/// emptied each run. drawing-2: panning and zooming that sheet's canvas in a warm window.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct DrawingBench {
    static let runs = 10
    static let steps = 60

    @Test func theBracketsFourViewsProject() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let empty = app.drawing.editor.document
        let sheet = try await DrawingBenchFixtures.bracketSheet(app)
        var samples = BenchSamples("drawing-1 bracket, four views projected (cache emptied)")
        let clock = ContinuousClock()
        for round in 0...Self.runs {
            try app.document.perform(.setDrawings(empty), name: "Test")
            app.refreshDrawing()
            await app.settle()
            await app.projectionCache.removeAll()
            // New view IDs each round: the session keeps what it applied per view and would see an unchanged view.
            var next = sheet
            for view in sheet.sheets[0].views {
                var copy = view
                copy.id = ViewID()
                next.sheets[0].removeView(view.id)
                next.sheets[0].setView(copy)
            }
            let start = clock.now
            try app.document.perform(.setDrawings(next), name: "Test")
            app.refreshDrawing()
            await app.settle()
            let end = clock.now
            guard round > 0 else { continue }
            samples.append(from: start, to: end)
        }
        for view in app.drawing.editor.document.sheets[0].views {
            #expect((app.drawing.editor.contents[view.id]?.projection?.lines.count ?? 0) > 0)
        }
        #expect(await app.projectionCache.kernelCalls >= 4 * Self.runs, "every round projected the four views again")
        print(samples.line(budget: 1000))
    }

    @Test func panningAndZoomingTheSheetWarm() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let sheet = try await DrawingBenchFixtures.bracketSheet(app)
        try app.document.perform(.setDrawings(sheet), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let warm = try await WarmBenchWindow(model: app)
        let editor = app.drawing.editor
        let start = editor.transform
        var cpu = BenchSamples("drawing-2-warm window-cpu (warm frame)")
        for step in 0..<Self.steps {
            editor.transform = SheetTransform(offset: start.offset + Vector2(-Double(step) * 8, -Double(step)), zoom: start.zoom)
            await app.settle()
            let milliseconds = warm.timedFrame()
            if step >= 5 { cpu.append(milliseconds) }
        }
        for step in 0..<Self.steps {
            let zoom = start.zoom * (step < Self.steps / 2 ? 1 + Double(step) * 0.03 : 1 + Double(Self.steps - step) * 0.03)
            editor.transform = start.zoomed(to: zoom, about: Vector2(700, 450))
            await app.settle()
            cpu.append(warm.timedFrame())
        }
        print(cpu.line(budget: Bench.frameBudget))
    }
}
#endif
