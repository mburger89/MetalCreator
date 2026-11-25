import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The sheet's views follow the graph (drawings plan R9, R19, R20): projections by the cache, one request per view, a newer
/// result replacing an older one.
@MainActor
struct DrawingProjectionTests {
    func extent(of lines: [ProjectedLine]) -> Double {
        var xs: [Double] = []
        for line in lines {
            if case .line(let a, let b) = line.curve { xs += [a.x, b.x] }
        }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }

    @Test func aBaseViewDrawsItsOutput() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        let id = try #require(await app.placeBaseView())
        let content = try #require(app.drawing.editor.contents[id])
        #expect(!content.isPending && content.problem == nil)
        #expect(app.lines(of: id).count == 4, "the box's four silhouette lines")
        #expect(extent(of: app.lines(of: id)) == 20)
        #expect(app.drawing.editor.picture?.strokes.contains { $0.view == id } == true)
    }

    @Test func anEditReprojects() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph)
        let id = try #require(await app.placeBaseView())
        let scale = try #require(app.drawing.editor.document.sheets.first?.scale.value)
        #expect(try #require(app.frameWidth(of: id)).isApproximately(10 * scale))
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(20)), name: "Test")
        await app.settle()
        #expect(extent(of: app.lines(of: id)) == 20)
        #expect(try #require(app.frameWidth(of: id)).isApproximately(20 * scale))
    }

    @Test func onlyViewsOfAChangedOutputReproject() async throws {
        var box = DrawingBox(width: 10)
        let other = box.builder.add(RectangleNode.self, ["width": .number(30)])
        let extrude = box.builder.add(ExtrudeNode.self, ["distance": .number(5)])
        let output = box.builder.add(OutputNode.self)
        box.builder.wire(other, "profile", to: extrude, "profile")
        box.builder.wire(extrude, "solid", to: output, "solid")
        let app = await AppModel.inDrawing(box.builder.graph)
        let editor = app.drawing.editor
        let (first, second) = (
            DrawingView(kind: .base, source: box.output.id, orientation: .standard(.front), center: Vector2(100, 150)),
            DrawingView(kind: .base, source: output.id, orientation: .standard(.front), center: Vector2(300, 150)))
        try app.document.perform(.setDrawings(replacing(replacing(editor.document, adding: first), adding: second)), name: "Add Views")
        await app.settle()
        let cache = app.projectionCache
        let before = await cache.kernelCalls
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(12)), name: "Test")
        await app.settle()
        let after = await cache.kernelCalls
        #expect(after == before + 1, "only the edited Output's view projected again (\(before) -> \(after))")
    }

    @Test func anUneditedMultiSolidOutputStaysAHitThroughTheCompound() async throws {
        let kernel = FakeKernel()
        await kernel.setCompoundHook { solids in solids[0] }
        var builder = GraphBuilder()
        let (rect, extrude) = (builder.add(RectangleNode.self), builder.add(ExtrudeNode.self))
        builder.wire(rect, "profile", to: extrude, "profile")
        let (rectB, extrudeB) = (builder.add(RectangleNode.self, ["width": .number(8)]), builder.add(ExtrudeNode.self))
        builder.wire(rectB, "profile", to: extrudeB, "profile")
        let merge = builder.add(MergeNode.self)
        builder.wire(extrude, "solid", to: merge, "a")
        builder.wire(extrudeB, "solid", to: merge, "b")
        let output = builder.add(OutputNode.self)
        builder.wire(merge, "list", to: output, "solid")
        let (rect2, extrude2, output2) = (builder.add(RectangleNode.self, ["width": .number(30)]),
                                         builder.add(ExtrudeNode.self), builder.add(OutputNode.self))
        builder.wire(rect2, "profile", to: extrude2, "profile")
        builder.wire(extrude2, "solid", to: output2, "solid")
        let app = await AppModel.inDrawing(builder.graph, kernel: kernel)
        let editor = app.drawing.editor
        let first = try #require(editor.sources.first { $0.id == output.id })
        let view = DrawingView(kind: .base, source: first.id, orientation: .standard(.front), center: Vector2(100, 100))
        try app.document.perform(.setDrawings(replacing(editor.document, adding: view)), name: "Add View")
        await app.settle()
        let cache = app.projectionCache
        let compounds = await cache.compoundCalls
        #expect(compounds == 1)
        let calls = await cache.kernelCalls
        try app.document.perform(.setInput(rect2.id, "width", .number(31)), name: "Test")
        await app.settle()
        #expect(await cache.compoundCalls == compounds, "the unedited Output's views stay hits")
        #expect(await cache.kernelCalls == calls)
    }

    /// A drawing document with `view` added to its first sheet.
    func replacing(_ document: DrawingDocument, adding view: DrawingView) -> DrawingDocument {
        var next = document
        next.sheets[0].setView(view)
        return next
    }

    @Test func thePendingProjectionStaysFaded() async throws {
        let kernel = FakeKernel()
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph, kernel: kernel)
        let id = try #require(await app.placeBaseView())
        let gate = HookGate()
        defer { gate.open() }
        await kernel.setProjectionHook { await gate.hold() }
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(20)), name: "Edit")
        await app.document.waitForEvaluation()
        app.refreshDrawing()
        await gate.waitUntilEntered()
        let content = try #require(app.drawing.editor.contents[id])
        #expect(content.isPending && extent(of: content.projection?.lines ?? []) == 10, "the old lines stay, faded")
        gate.open()
        await app.settle()
        #expect(app.drawing.editor.contents[id]?.isPending == false)
        #expect(extent(of: app.lines(of: id)) == 20)
    }

    @Test func aRemovedOutputLeavesAFrameAndUndoRestoresIt() async throws {
        let box = DrawingBox()
        let app = await AppModel.inDrawing(box.graph)
        let id = try #require(await app.placeBaseView())
        try app.document.perform(.removeNode(box.output.id), name: "Delete")
        await app.settle()
        let content = try #require(app.drawing.editor.contents[id])
        #expect(content.problem == DrawingProjector.removedSentence)
        #expect(app.drawing.editor.picture?.viewFrames[id] != nil, "an empty frame is left")
        app.undo()
        await app.settle()
        #expect(app.drawing.editor.contents[id]?.problem == nil)
        #expect(app.lines(of: id).count == 4, "the view draws again")
    }

    @Test func aFailedOutputFadesTheLastProjection() async throws {
        let box = DrawingBox()
        let app = await AppModel.inDrawing(box.graph)
        let id = try #require(await app.placeBaseView())
        // A rectangle with no size the kernel can build fails the Extrude.
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(0)), name: "Break")
        await app.settle()
        guard case .error? = app.document.results[box.extrude.id]?.state else {
            Issue.record("the edit was meant to make the Extrude fail: \(String(describing: app.document.results[box.extrude.id]?.state))")
            return
        }
        let content = try #require(app.drawing.editor.contents[id])
        #expect(content.problem != nil, "the failure shows")
        #expect(content.projection?.lines.count == 4, "and the last projection stays")
        #expect(content.isPending, "faded, as an evaluating Output's is")
        let problem = try #require(content.problem)
        let picture = try #require(app.drawing.editor.picture)
        let notice = try #require(picture.texts.first { $0.original == problem })
        #expect(notice.isNotice && notice.view == id, "the sentence is on the sheet, under the view")
        let frame = try #require(picture.viewFrames[id])
        #expect(notice.origin.y < frame.min.y)
    }

    @Test func aMeshOutputWarns() async throws {
        var box = DrawingBox()
        let sphere = box.builder.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let mesh = box.builder.add(MeshNode.self, ["preview resolution": .number(1)])
        let meshOutput = box.builder.add(OutputNode.self)
        box.builder.wire(sphere, "implicit", to: mesh, "implicit")
        box.builder.wire(mesh, "mesh", to: meshOutput, "mesh")
        let app = await AppModel.inDrawing(box.builder.graph)
        let editor = app.drawing.editor
        let view = DrawingView(kind: .base, source: meshOutput.id, orientation: .standard(.front), center: Vector2(100, 100))
        try app.document.perform(.setDrawings(replacing(editor.document, adding: view)), name: "Add View")
        await app.settle()
        #expect(editor.contents[view.id]?.problem == DrawingProjector.onlyMeshesSentence)
    }

    @Test func alignmentSurvivesAnEdit() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph)
        let parent = try #require(await app.placeBaseView(at: Vector2(100, 150)))
        let editor = app.drawing.editor
        editor.press(.projectedView)
        editor.primaryChanged(to: editor.transform.screenPoint(Vector2(100, 150)), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(Vector2(200, 150)), modifiers: [])
        await app.settle()
        let right = try #require(editor.document.sheets[0].views.first { $0.id != parent }?.id)
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(40)), name: "Grow")
        await app.settle()
        let frames = try #require(editor.picture?.viewFrames)
        #expect(try #require(frames[parent]).center.y.isApproximately(try #require(frames[right]).center.y))
    }

    @Test func massFollowsTheDensity() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph)
        _ = await app.placeBaseView()
        let editor = app.drawing.editor
        let sheet = try #require(editor.currentSheet)
        #expect(editor.facts.massText == nil, "no density, no mass")
        editor.setDensity(2.7)
        await app.settle()
        #expect(editor.facts.massText == "2.7 g", "10 x 10 x 10 mm is 1 cm3")
        editor.setDensity(nil)
        await app.settle()
        #expect(editor.facts.massText == nil)
        _ = sheet
    }

    @Test func projectAllReadsEverySheet() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        let first = try #require(await app.placeBaseView())
        app.drawing.editor.addSheet()
        let snapshot = await app.drawing.projectAll()
        #expect(snapshot.contents[first]?.projection?.lines.count == 4)
        #expect(snapshot.facts.count == 2)
    }

    @Test func theCacheIsEmptiedOnOpen() async throws {
        let app = await AppModel.inDrawing(DrawingBox().graph)
        _ = await app.placeBaseView()
        let before = app.projectionCache
        #expect(await before.count == 1)
        let url = temporaryURL("empty.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try GraphFileIO.encode(GraphFile()).write(to: url)
        try app.open(url)
        await app.settle()
        #expect(await app.projectionCache.count == 0)
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-6) -> Bool { abs(self - other) <= tolerance }
}
