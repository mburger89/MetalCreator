import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// The edits the app shell makes (viewport handle drags, edge picks, New Sketch on Face, the sketch editor's commits)
/// name their undo steps (named undo steps).
@MainActor
struct AppUndoNameTests {
    @Test func aHandleDragIsOneStepCalledDragHandle() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let id = try #require(app.viewport.handles.first?.id)
        app.handleChanged(id, 12, .changed)
        app.handleChanged(id, 14, .changed)
        app.handleChanged(id, 16, .ended)
        #expect(app.document.undoName == "Drag Handle")
        app.document.undo()
        #expect(app.document.undoName == nil, "the drag was one step")
    }

    @Test func pickingEdgesIntoARuleAndSelectingEdgesOfAFaceAreNamed() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.press(.pickEdgesInView, on: rule.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.finishPick()
        #expect(app.document.undoName == "Pick Edges", "into an existing rule")

        let solid = try #require(app.viewport.items.first?.solid)
        let edges = [EdgeID(1), EdgeID(3)]
        app.selectEdgesOfFace(ViewportFaceRef(solidIndex: 0, face: FaceID(1)), solid.topology.picks(for: edges), edges)
        #expect(app.document.undoName == "Select Edges of Face", "a new rule from the face menu")
    }

    @Test func pickingOnAFeatureFedByAnotherRuleAddsARuleCalledPickEdges() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let all = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, ["radius": .number(1)], at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: all, "solid")
        builder.wire(all, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.beginPick(for: fillet.id)
        let session = try #require(app.pick)
        #expect(session.rule == nil)
        app.finishPick()
        #expect(app.document.undoName == "Pick Edges")
    }

    @Test func newSketchOnFaceIsOneNamedStep() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .newSketchOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
        #expect(app.document.undoName == "New Sketch on Face")
    }

    @Test func aSketchCommitIsNamedByItsFixedStepName() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical", name: "Add Constraint"))
        #expect(app.document.undoName == "Add Constraint")
        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical", name: "  "))
        #expect(app.document.undoName == "Edit Sketch", "a commit with a blank name")
        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical"))
        #expect(app.document.undoName == "Edit Sketch", "a commit made without a name")

        editor.choose(.line)
        editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        await app.settle()
        #expect(app.document.undoName == "Add Line")
    }

    @Test func aRenamedDimensionNeverReachesTheMenu() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        let dimension = try #require(editor.sketch.dimensionIDs.first)
        editor.rename(dimension, to: "Plate width")
        await app.settle()
        #expect(app.document.undoName == "Rename Dimension")
        #expect(app.document.undoName != "Rename d1 to Plate width", "the typed name never reaches the step name")
        editor.setValue("55", of: dimension)
        await app.settle()
        #expect(app.document.undoName == "Change Dimension")
    }
}
