#if canImport(CreatorOCCT)
import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Drawings spec benchmarks, release, idle Mac; prints `BENCH drawing-1`, `drawing-2-warm`, `drawing-3`, `drawing-3-warm`, `drawing-4`, `drawing-5` and `drawing-5-warm` lines. Recorded, not gated.
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
        #expect(try #require(app.drawing.editor.picture).annotationReports.values.allSatisfy { $0.status == .held }, "none lost")
        print(cpu.line(budget: Bench.frameBudget))
    }

    /// drawing-4: a straight section of the bracket's Top view through a row of holes, from the edit that adds it (the four base
    /// views already drawn) to its landing, projection cache emptied, 10 runs. Each round gives the section a new view ID, so the
    /// session cuts and projects again.
    @Test func aSectionLands() async throws {
        guard Bench.requireRelease() else { return }
        let (app, _) = try await makeBracketBenchApp()
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let withSection = try await DrawingBenchFixtures.sectionedBracketSheet(app)
        var base = withSection
        let section = try #require(withSection.sheets[0].views.first { $0.kind == .section })
        base.sheets[0].removeView(section.id)
        try app.document.perform(.setDrawings(base), name: "Test")
        app.refreshDrawing()
        await app.settle()
        var samples = BenchSamples("drawing-4 bracket, a straight section through the holes (cache emptied)")
        let clock = ContinuousClock()
        var lastID = section.id
        for round in 0...Self.runs {
            try app.document.perform(.setDrawings(base), name: "Test")
            app.refreshDrawing()
            await app.settle()
            await app.projectionCache.removeAll()
            let before = await app.projectionCache.cutCalls
            var copy = section
            copy.id = ViewID()
            lastID = copy.id
            var next = base
            next.sheets[0].setView(copy)
            let start = clock.now
            try app.document.perform(.setDrawings(next), name: "Test")
            app.refreshDrawing()
            await app.settle()
            let end = clock.now
            #expect(await app.projectionCache.cutCalls > before, "round \(round) cut the part again")
            guard round > 0 else { continue }
            samples.append(from: start, to: end)
        }
        let content = try #require(app.drawing.editor.contents[lastID])
        #expect(content.problem == nil && !content.hatch.isEmpty && (content.projection?.lines.count ?? 0) > 0)
        print(samples.line(budget: 1000))
    }

    /// drawing-5: a sheet of ten parts, the Assembly View in Front with its Top and Right projected views, from the edit that adds
    /// them to the last projection landing, projection cache emptied, 10 runs. New view IDs each round.
    @Test func anAssemblySheetProjects() async throws {
        guard Bench.requireRelease() else { return }
        let app = AppModel(kernel: OCCTKernel())
        let outputs = try DrawingBenchFixtures.addAssemblyParts(to: app.document, parts: 10)
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let empty = app.drawing.editor.document
        let sheet = DrawingBenchFixtures.assemblySheet(app, outputs: outputs)
        var samples = BenchSamples("drawing-5 ten-part assembly, three views projected (cache emptied)")
        let clock = ContinuousClock()
        for round in 0...Self.runs {
            try app.document.perform(.setDrawings(empty), name: "Test")
            app.refreshDrawing()
            await app.settle()
            await app.projectionCache.removeAll()
            var ids: [ViewID: ViewID] = [:]
            var next = sheet
            for view in sheet.sheets[0].views {
                var copy = view
                copy.id = ViewID()
                ids[view.id] = copy.id
                next.sheets[0].removeView(view.id)
                next.sheets[0].setView(copy)
            }
            for view in next.sheets[0].views {
                guard var alignment = view.alignment, let parent = ids[alignment.parent] else { continue }
                var moved = view
                alignment.parent = parent
                moved.alignment = alignment
                next.sheets[0].setView(moved)
            }
            let before = await app.projectionCache.kernelCalls
            let start = clock.now
            try app.document.perform(.setDrawings(next), name: "Test")
            app.refreshDrawing()
            await app.settle()
            let end = clock.now
            #expect(await app.projectionCache.kernelCalls >= before + 3, "round \(round) projected the three views again")
            guard round > 0 else { continue }
            samples.append(from: start, to: end)
        }
        for view in app.drawing.editor.document.sheets[0].views {
            let content = app.drawing.editor.contents[view.id]
            #expect((content?.projection?.lines.count ?? 0) > 0 && content?.parts.count == 10)
        }
        print(samples.line(budget: 1000))
    }

    /// drawing-5-warm: 60 pan steps and 60 zoom steps of the ten-part sheet with ten balloons and the parts list, warm window CPU
    /// per frame.
    @Test func panningAndZoomingTheAssemblySheetWarm() async throws {
        guard Bench.requireRelease() else { return }
        let app = AppModel(kernel: OCCTKernel())
        let outputs = try DrawingBenchFixtures.addAssemblyParts(to: app.document, parts: 10)
        app.setMode(.drawing)
        app.drawing.editor.addSheet()
        await app.settle()
        let document = try await DrawingBenchFixtures.balloonedAssemblySheet(app, outputs: outputs)
        try app.document.perform(.setDrawings(document), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let editor = app.drawing.editor
        let balloons = editor.document.sheets[0].annotations.filter { if case .balloon = $0.kind { true } else { false } }
        #expect(balloons.count == 10)
        let reports = balloons.compactMap { editor.picture?.annotationReports[$0.id] }
        #expect(reports.count == 10 && reports.allSatisfy { $0.status == .held }, "every balloon held")
        let warm = try await WarmBenchWindow(model: app)
        let start = editor.transform
        var cpu = BenchSamples("drawing-5-warm window-cpu (warm frame, ten parts, ten balloons, parts list)")
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
        let held = balloons.compactMap { editor.picture?.annotationReports[$0.id] }.filter { $0.status == .held }.count
        #expect(held == 10, "every balloon still held after the run")
        print(cpu.line(budget: Bench.frameBudget))
    }
}
#endif
