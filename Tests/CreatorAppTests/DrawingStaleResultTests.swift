import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Synchronization
import Testing
@testable import CreatorApp

/// What a view shows while its result is out of date, and what the session keeps (drawings plan R19): a superseded request never
/// publishes, an Output still evaluating keeps the old lines faded, the volume cache holds only the solids asked for.
@MainActor
struct DrawingStaleResultTests {
    func extent(of lines: [ProjectedLine]) -> Double {
        var xs: [Double] = []
        for line in lines {
            if case .line(let a, let b) = line.curve { xs += [a.x, b.x] }
        }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }

    @Test func aSupersededRequestNeverPublishes() async throws {
        let kernel = FakeKernel()
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph, kernel: kernel)
        let id = try #require(await app.placeBaseView())
        let gate = HookGate()
        defer { gate.open() }
        // Only the first projection is held; the second passes at once, so it lands first.
        let calls = Mutex(0)
        await kernel.setProjectionHook {
            let isFirst = calls.withLock { count -> Bool in
                count += 1
                return count == 1
            }
            if isFirst { await gate.hold() }
        }
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(20)), name: "First")
        await app.document.waitForEvaluation()
        app.refreshDrawing()
        await gate.waitUntilEntered()
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(30)), name: "Second")
        await app.document.waitForEvaluation()
        app.refreshDrawing()
        // The older request is cancelled at once and finishes with "cancelled": that must never be published.
        var published: [String] = []
        for _ in 0..<2000 where extent(of: app.lines(of: id)) != 30 {
            if let problem = app.drawing.editor.contents[id]?.problem { published.append(problem) }
            await Task.yield()
        }
        #expect(published.isEmpty, "a superseded request's result was published: \(published)")
        #expect(extent(of: app.lines(of: id)) == 30, "the second edit's lines landed first")
        gate.open()
        // The superseded task is no longer in `flights`, so settle doesn't wait for it: give it ample turns to land.
        for _ in 0..<3000 {
            await Task.yield()
            if extent(of: app.lines(of: id)) != 30 || app.drawing.editor.contents[id]?.problem != nil { break }
        }
        await app.settle()
        #expect(app.drawing.editor.contents[id]?.problem == nil, "the older request's late result is dropped")
        #expect(extent(of: app.lines(of: id)) == 30, "the older request's late result is dropped")
        #expect(app.drawing.editor.contents[id]?.isPending == false)
    }

    @Test func staleLinesStayFadedWhileTheOutputEvaluates() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph)
        let id = try #require(await app.placeBaseView())
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(20)), name: "Edit")
        app.refreshDrawing()
        // Whenever the Output's result is still "evaluating", the view must be faded: the invariant is checked at every
        // suspension until both the evaluation and the projection are done (the main actor can't apply the report in between).
        var sawEvaluating = false
        var steps = 0
        while app.document.isEvaluating || app.drawing.isProjecting, steps < 10_000 {
            if case .evaluating? = app.document.results[box.output.id]?.state {
                sawEvaluating = true
                let content = try #require(app.drawing.editor.contents[id])
                #expect(content.isPending, "the part is being rebuilt, so what shows is out of date")
                #expect(extent(of: content.projection?.lines ?? []) == 10)
            }
            await Task.yield()
            steps += 1
        }
        #expect(sawEvaluating)
        await app.settle()
        #expect(app.drawing.editor.contents[id]?.isPending == false)
        #expect(extent(of: app.lines(of: id)) == 20)
    }

    @Test func theVolumeCacheKeepsOnlyTheSolidsAsked() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph)
        _ = await app.placeBaseView()
        app.drawing.editor.setDensity(2.7)
        await app.settle()
        for width in [12.0, 14, 16] {
            try app.document.perform(.setInput(box.rectangle.id, "width", .number(width)), name: "Edit")
            await app.settle()
        }
        #expect(app.drawing.volumes.count == 1, "only the current solid is kept (\(app.drawing.volumes.count))")
        #expect(app.drawing.editor.facts.massText != nil)
    }
}
