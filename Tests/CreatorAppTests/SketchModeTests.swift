import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// Sketch mode (sketcher spec §8): "Edit sketch" opens the node's sketch in the viewport, every editor commit is one
/// `setInput` undo step, undo reloads it, Finish leaves, and an exposed dimension's value and wire live in one place
/// (S4 → S5 handoff).
@MainActor
struct SketchModeTests {
    func openSketch(_ builder: GraphBuilder, _ node: Node) async throws -> AppModel {
        let app = await makeApp(builder.graph)
        app.editor.selection = [node.id]
        app.editor.press(.editSketch, on: node.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        return app
    }

    func storedSketch(_ app: AppModel, _ node: Node) -> Sketch? {
        if case .sketch(let sketch)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] { return sketch }
        return nil
    }

    @Test func theSketchNodesInspectorHasEditSketch() {
        #expect(SketchNode.inspector.first?.controls == [.button(title: "Edit sketch", action: .editSketch)])
    }

    @Test func editSketchLooksAtThePlaneDimsTheModelAndTakesThePointer() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(on: .xz))
        let app = try await openSketch(builder, box.sketch)
        let session = try #require(app.sketch)
        #expect(session.node == box.sketch.id)
        #expect(app.viewport.tool === session.editor)
        await app.viewport.waitForAnimation()
        #expect(app.viewport.pose.projection == .orthographic)
        #expect((app.viewport.pose.toEye - Plane.xz.normal).length < 1e-9, "looking straight at the sketch plane")
        #expect(!app.viewport.items.isEmpty && app.viewport.items.allSatisfy(\.isGhost), "the model is dimmed")
        #expect(app.viewport.handles.isEmpty)
        #expect(app.viewport.overlay == session.editor.overlay, "the sketch is drawn over it")
        #expect(app.viewport.overlay.gridPlane == .xz)
    }

    @Test func eachCommitIsOneUndoStepAndUndoReloadsTheEditor() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        let before = storedSketch(app, box.sketch)
        editor.choose(.line)
        editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        await app.settle()
        #expect(storedSketch(app, box.sketch) == editor.sketch, "the node holds what the editor shows, remembered")
        app.document.undo()
        await app.settle()
        #expect(storedSketch(app, box.sketch) == before)
        #expect(editor.sketch.entities.count == 8, "the editor shows the sketch as it was")
        #expect(app.sketch != nil, "undo stays in sketch mode")
        #expect(app.document.canUndo == false)
    }

    @Test func aStrokeInProgressSurvivesSceneRefreshes() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        editor.choose(.line)
        editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        app.editor.selection = []
        await app.settle()
        editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        #expect(app.document.canUndo, "the line was drawn from the first click")
    }

    @Test func theOverlayFollowsTheEditorBetweenSceneRefreshes() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let session = try #require(app.sketch)
        session.editor.choose(.line)
        session.editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        session.editor.hover(at: Vector2(10, 70), tolerance: 1, modifiers: [])
        await session.settle()
        #expect(app.viewport.overlay.lines.contains { $0.tint == .preview }, "the rubber band reaches the viewport")
    }

    @Test func finishingGivesTheViewportBack() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        try #require(app.sketch).editor.finish()
        await app.settle()
        #expect(app.sketch == nil && app.viewport.tool == nil)
        #expect(app.viewport.overlay.isEmpty)
        #expect(app.viewport.items.allSatisfy { !$0.isGhost })
    }

    @Test func removingTheNodeLeavesSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        try app.document.perform(.removeNode(box.sketch.id))
        await app.settle()
        #expect(app.sketch == nil && app.viewport.tool == nil)
    }

    @Test func aNewDocumentLeavesSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let old = app.viewport
        #expect(!app.isEdited, "opening a sketch isn't an edit, so New doesn't ask")
        app.newDocument()
        await app.settle()
        #expect(app.sketch == nil && old.tool == nil)
    }

    @Test func anExposedDimensionsConstantIsFoldedIntoTheSketchAndCleared() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true), values: ["width": .number(70)])
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        #expect(editor.dimensionRows.first?.value == "70 mm", "the editor shows what the node evaluates")
        let height = try #require(editor.sketch.dimensionIDs.last)
        editor.setValue("30", of: height)
        await app.settle()
        let node = try #require(app.document.graph.nodes[box.sketch.id])
        #expect(node.inputValues["width"] == nil, "the value lives in the sketch alone")
        let stored = try #require(storedSketch(app, box.sketch))
        #expect(stored.dimensions.values.first { $0.name == "width" }?.value == 70)
    }

    @Test func renamingAnExposedDimensionMovesItsWireAndUnexposingDropsIt() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let number = builder.add(NumberNode.self, ["value": .number(75)], at: Vector2(0, 200))
        builder.wire(number, "value", to: box.sketch, "width")
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        let width = try #require(editor.sketch.dimensionIDs.first)
        editor.rename(width, to: "w")
        await app.settle()
        let to = { (socket: SocketName) in app.document.graph.incomingLink(to: Endpoint(node: box.sketch.id, socket: socket)) }
        #expect(to("width") == nil && to("w")?.from.node == number.id, "the wire follows the rename")
        #expect(app.document.results[box.sketch.id]?.state.isSuccess == true)
        editor.setExposed(false, of: width)
        await app.settle()
        #expect(to("w") == nil, "no socket, no wire")
        app.document.undo()
        app.document.undo()
        await app.settle()
        #expect(to("width")?.from.node == number.id, "undo puts the wire back")
    }

    @Test func reservedNamesAreRefused() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        let width = try #require(editor.sketch.dimensionIDs.first)
        editor.rename(width, to: "references")
        #expect(editor.refusal?.contains("taken by the Sketch node") == true)
        #expect(!app.document.canUndo)
    }

    @Test func aWiredPlaneWithoutAResultIsRefusedPlainly() async throws {
        var builder = GraphBuilder()
        var sketch = rectangleSketch()
        sketch.plane = .wired
        let node = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
        let app = try await openSketch(builder, node)
        #expect(app.sketch == nil)
        #expect(app.alert != nil)
    }

    /// Review Focus 1: Esc and ⏎ are the sketch's button shortcuts, which run before the palette's keys, so with the
    /// add-node palette open they close it and the sketch stays open.
    @Test func escapeAndFinishCloseTheAddNodePaletteFirst() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        app.editor.openPalette()
        editor.escape()
        #expect(app.editor.palette == nil && app.sketch != nil)
        app.editor.openPalette()
        editor.finish()
        #expect(app.editor.palette == nil && app.sketch != nil)
        editor.finish()
        #expect(app.sketch == nil)
    }

    /// Review Focus 5: an exposed dimension named like a setting (a hand-edited file) is never a socket, so storing
    /// the sketch never clears that setting, even when the dimension stops being exposed.
    @Test func aReservedExposedNameNeverClearsTheSketchSetting() async throws {
        var sketch = rectangleSketch(exposed: true)
        let width = try #require(sketch.dimensions.first { $0.value.name == "width" }?.key)
        sketch.dimensions[width]?.name = "sketch"
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let app = try await openSketch(builder, box.sketch)
        try #require(app.sketch?.editor).setExposed(false, of: width)
        await app.settle()
        let stored = try #require(storedSketch(app, box.sketch))
        #expect(stored.dimensions[width]?.isExposed == false, "the edit is stored, and the sketch setting with it")
        #expect(app.document.results[box.sketch.id]?.state.isSuccess == true)
    }
}
