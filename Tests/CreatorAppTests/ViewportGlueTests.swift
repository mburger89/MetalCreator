import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// The viewport's events, turned into graph commands and document state (M4 carry-over): handle drags, "Show
/// Producing Node", the settled camera and the home view, and a press giving the keys back.
@MainActor
struct ViewportGlueTests {
    @Test func draggingAHandleEditsItsInputAsOneUndoStep() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let id = try #require(app.viewport.handles.first?.id)
        app.handleChanged(id, 12, .changed)
        app.handleChanged(id, 14, .changed)
        app.handleChanged(id, 15, .ended)
        await app.settle()
        #expect(app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(15))
        #expect(app.viewport.items.first?.solid.bounds.size.z == 15)
        app.document.undo()
        #expect(app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(10))
        app.handleChanged(id, 11, .changed)
        app.handleChanged(id, 11, .ended)
        app.document.undo()
        #expect(app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(10),
                "the next drag is its own step")
    }

    /// A click on a knob without moving reports the value it already has: no undo step, and redo survives.
    @Test func aHandleClickWithoutMovingRecordsNothing() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let id = try #require(app.viewport.handles.first?.id)
        app.handleChanged(id, 10, .ended)
        #expect(!app.document.canUndo, "the value didn't change")
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(12)))
        app.document.undo()
        app.handleChanged(id, 10, .changed)
        app.handleChanged(id, 10, .ended)
        #expect(app.document.canRedo, "a still click doesn't clear redo")
        #expect(!app.document.canUndo)
        app.handleChanged(id, 13, .changed)
        app.handleChanged(id, 10, .ended)
        app.handleChanged(id, 11, .ended)
        app.document.undo()
        #expect(app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(10),
                "a drag that returns to its start still ends its step")
    }

    /// After New or Open the old viewport may still be drawn or report a settling camera; its events must not
    /// reach the new document.
    @Test func aReplacedViewportsEventsDontReachTheNewDocument() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let old = app.viewport
        let id = try #require(old.handles.first?.id)
        app.newDocument()
        var released = 0
        app.releaseTextFocus = { released += 1 }
        old.events.cameraSettled(CameraPose(target: Vector3(1, 2, 3), distance: 50))
        old.events.homeChanged(CameraPose(target: Vector3(1, 2, 3), distance: 50))
        old.events.handleChanged(id, 30, .ended)
        old.events.pressed()
        old.events.showProducingNode(box.extrude.id)
        #expect(old.events.nodeName(box.extrude.id) == nil)
        #expect(app.document.viewState.camera == nil && app.document.viewState.homeCamera == nil)
        #expect(!app.document.canUndo && !app.isEdited)
        #expect(released == 0)
        #expect(app.editor.selection.isEmpty)
        app.viewport.events.pressed()
        #expect(released == 1, "the new viewport's events still arrive")
    }

    @Test func showProducingNodeSelectsItAndScrollsTheGraphToIt() async throws {
        var builder = GraphBuilder()
        let box = builder.box(at: Vector2(600, 400))
        let file = GraphFile(graph: builder.graph, viewState: ViewState(dock: .hidden))
        let app = AppModel(kernel: FakeKernel(), file: file)
        await app.settle()
        app.showProducingNode(box.extrude.id)
        #expect(app.editor.isPanelVisible)
        #expect(app.editor.selection == [box.extrude.id])
        let node = try #require(app.document.graph.nodes[box.extrude.id])
        #expect(app.editor.transform.toScreen(app.editor.displayOrigin(of: node)) == AppLayout.revealPoint)
        #expect(app.viewport.events.nodeName(box.extrude.id) == "Extrude")
    }

    @Test func theCameraReachesTheDocumentOnlyWhenItComesToRest() async {
        let app = await makeApp()
        #expect(app.document.viewState.camera == nil)
        app.viewport.pointerDown(at: ScreenPoint(600, 400), modifiers: [])
        app.viewport.pointerDragged(to: ScreenPoint(640, 420))
        #expect(app.document.viewState.camera == nil, "not while the drag moves it")
        app.viewport.pointerUp(at: ScreenPoint(640, 420))
        #expect(app.document.viewState.camera == app.viewport.pose)
        app.viewport.perform(.setHome)
        #expect(app.document.viewState.homeCamera == app.viewport.pose)
        #expect(!app.isEdited, "the camera is saved with the file but isn't an edit")
    }

    /// The scene follows the whole view state (the dock lives there), so a canvas pan or a settled camera wakes it.
    /// Neither changes what's drawn, so neither may restart the viewport's mesh load (M4 carry-over).
    @Test func panningTheCanvasOrSettlingTheCameraDoesntRebuildTheScene() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let generation = app.viewport.sceneGeneration
        let handles = app.viewport.handles
        app.editor.transform = app.editor.transform.panned(by: Vector2(30, 10))
        await app.settle()
        app.viewport.pointerDown(at: ScreenPoint(600, 400), modifiers: [])
        app.viewport.pointerDragged(to: ScreenPoint(640, 420))
        app.viewport.pointerUp(at: ScreenPoint(640, 420))
        await app.settle()
        #expect(app.document.viewState.camera != nil, "the camera settled into the document")
        #expect(app.viewport.sceneGeneration == generation, "the same scene isn't shown again")
        #expect(app.viewport.handles == handles)
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(25)))
        await app.settle()
        #expect(app.viewport.sceneGeneration == generation + 1, "a new result still shows")
    }

    @Test func aPressOnTheViewportOrTheCanvasReleasesTextFocus() async {
        let app = await makeApp()
        var released = 0
        app.releaseTextFocus = { released += 1 }
        app.viewport.pointerDown(at: ScreenPoint(500, 400), modifiers: [])
        app.viewport.pointerUp(at: ScreenPoint(500, 400))
        #expect(released == 1)
        app.graphInput.releaseTextFocus?()
        #expect(released == 2, "the graph panel's press goes through the same hook")
    }

    @Test func aViewportPressCommitsATypedInspectorValue() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        guard case .slider(let field, _)? = app.editor.inspectorPage.sections.first?.rows.dropFirst().first else {
            Issue.record("no Distance slider"); return
        }
        app.editor.notePendingEntry(PendingEntry(text: "33", commit: { app.editor.setNumber(field, to: $0) }))
        app.viewport.pointerDown(at: ScreenPoint(500, 400), modifiers: [])
        #expect(app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(33))
    }
}
