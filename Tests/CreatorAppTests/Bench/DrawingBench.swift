#if canImport(CreatorOCCT)
import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import Testing
@testable import CreatorApp

/// Drawings spec benchmarks, release, idle Mac; prints `BENCH drawing-1`, `drawing-2-warm`, `drawing-3` and `drawing-3-warm` lines. Recorded, not gated.
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

    /// drawing-3: composing the bracket sheet with its 30 dimensions (frame, title block, views, annotations), views already
    /// projected, 50 composes. Recorded only; plan R24 pulls in resolution caching when the median is over 4 ms.
    @Test func composingTheAnnotatedSheet() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.annotatedBracketSheet(app)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let editor = app.drawing.editor
        let sheet = try #require(editor.document.sheets.first)
        #expect(sheet.annotations.count == DrawingBenchFixtures.dimensionCount)
        var samples = BenchSamples("drawing-3 bracket sheet with 30 dimensions, composed")
        let clock = ContinuousClock()
        var held = 0
        for round in 0...50 {
            let start = clock.now
            let picture = SheetComposer.compose(
                sheet, in: editor.document, contents: editor.contents, facts: editor.facts, units: editor.units,
                remembered: editor.remembered)
            let end = clock.now
            held = picture.annotationReports.values.filter { $0.status == .held }.count
            guard round > 0 else { continue }
            samples.append(from: start, to: end)
        }
        #expect(held == DrawingBenchFixtures.dimensionCount, "every dimension was held and drawn: \(held)")
        print(samples.line(budget: 4))
    }

    /// drawing-3-warm: 60 steps of dragging one dimension away from its edge, each a new document landing on the sheet (the
    /// whole annotated sheet recomposed and redrawn), warm window CPU per frame.
    @Test func draggingADimensionWarm() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.annotatedBracketSheet(app)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let warm = try await WarmBenchWindow(model: app)
        var dragged = document
        let target = try #require(dragged.sheets[0].annotations.first { annotation in
            if case .dimension = annotation.kind { true } else { false }
        })
        var cpu = BenchSamples("drawing-3-warm window-cpu (warm frame, dimension dragged)")
        for step in 0..<Self.steps {
            var moved = target
            if case .dimension(var dimension) = target.kind {
                dimension.placement.offset += Double(step) * 0.5
                moved.kind = .dimension(dimension)
            }
            dragged.sheets[0].setAnnotation(moved)
            try app.document.perform(.setDrawings(dragged), name: "Test")
            app.refreshDrawing()
            await app.settle()
            let milliseconds = warm.timedFrame()
            if step >= 5 { cpu.append(milliseconds) }
        }
        print(cpu.line(budget: Bench.frameBudget))
    }
}
#endif
