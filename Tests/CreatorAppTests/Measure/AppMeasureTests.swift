import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorViewport

/// Measure in the app: what starts it, what it excludes, and that it never selects a node or touches the document.
@MainActor
struct AppMeasureTests {
    private func sketchedBox() -> (graph: Graph, sketch: Node) {
        var sketch = Sketch(plane: .fixed(.xy))
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(60, 0))
        let line = sketch.addLine(from: a, to: b)
        sketch.add(.fix(a, at: .zero))
        sketch.add(.horizontal(line))
        _ = sketch.addDimension(.length(line), value: 60)
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        return (builder.graph, box.sketch)
    }

    @Test func clicksNeverSelectNodes() async throws {
        let fixture = await MeasureAppFixture.open()
        let app = fixture.app
        let top = try #require(fixture.solid.topology.faces.first { $0.kind == .plane && $0.normal == .unitZ })
        app.viewport.pick = { _ in .face(solid: 0, top.id) }
        app.setMeasure(true)
        app.viewport.click(at: ScreenPoint(700, 450))
        #expect(app.editor.selection.isEmpty)
        #expect(app.measure?.picks == [.face(solid: 0, top.id)])
        app.setMeasure(false)
        app.viewport.click(at: ScreenPoint(700, 450))
        #expect(!app.editor.selection.isEmpty, "without Measure the same click selects the feature")
    }

    @Test func measureNeverMarksTheDocumentEdited() async throws {
        let fixture = await MeasureAppFixture.open()
        let app = fixture.app
        let graph = app.document.graph
        app.setMeasure(true)
        fixture.click(fixture.target(fixture.verticals[0]))
        fixture.click(fixture.target(fixture.verticals[1]))
        await app.settle()
        #expect(!app.isEdited && !app.document.canUndo && app.document.undoName == nil)
        #expect(app.document.graph == graph)
        app.setMeasure(false)
        #expect(!app.isEdited && app.viewport.tool == nil)
    }

    @Test func sketchingEndsMeasure() async throws {
        let (graph, sketchNode) = sketchedBox()
        let app = await makeApp(graph)
        app.setMeasure(true)
        let session = try #require(app.measure)
        #expect(app.viewport.tool === session)
        app.beginSketch(for: sketchNode.id)
        #expect(app.measure == nil)
        #expect(app.viewport.tool === app.sketch?.editor)
        app.finishSketch()
        #expect(app.viewport.tool == nil)
    }

    @Test func measureIsRefusedWhileSketching() async throws {
        let (graph, sketchNode) = sketchedBox()
        let app = await makeApp(graph)
        app.beginSketch(for: sketchNode.id)
        app.setMeasure(true)
        #expect(app.measure == nil)
        #expect(app.viewport.tool === app.sketch?.editor)
    }

    @Test func startingDEndsMeasureAndMeasureEndsD() async throws {
        let fixture = await MeasureAppFixture.open()
        let app = fixture.app
        app.setMeasure(true)
        #expect(app.beginModelDimension())
        #expect(app.measure == nil && app.viewport.tool == nil && app.modelDimension != nil)
        app.setMeasure(true)
        #expect(app.measure != nil && app.modelDimension == nil)
    }

    @Test func endingLeavesAnotherToolAlone() async throws {
        let fixture = await MeasureAppFixture.open()
        let app = fixture.app
        app.setMeasure(true)
        let other = ModifierProbeTool()
        app.viewport.tool = other
        app.setMeasure(false)
        #expect(app.viewport.tool === other)
    }

    @Test func theKeyMStartsMeasureOverTheViewportAndNotOverTheGraph() async throws {
        var builder = GraphBuilder()
        _ = builder.box(at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey("m")
        try await app.window.runUntilIdle()
        #expect(app.model.measure == nil)
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey("m")
        try await app.window.runUntilIdle()
        #expect(app.model.measure != nil && app.model.viewport.tool === app.model.measure)
    }
}
