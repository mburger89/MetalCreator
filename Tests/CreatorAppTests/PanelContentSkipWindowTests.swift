import CreatorEditor
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The panels around the canvas are `.equatable()` (MetalUI C14-d): `GraphPanel`, `GraphPanelBody`, `GraphCanvas`,
/// `CanvasSurface`, `NodeLibraryView` and `InspectorPanel`, each equal while it holds the same model and input objects. A
/// view whose models read nothing that changed is skipped, and one whose observed read changed evaluates. These count that in
/// the app's real window through `FrameWork`'s `contentEvaluations` (never milliseconds), and compare each incremental frame
/// with the picture the window draws when every view evaluates afresh.
@MainActor
struct PanelContentSkipWindowTests {
    struct Fixture {
        let app: AppWindow
        let node: Node
    }

    /// Two nodes on screen with the node library shown (the inspector is always docked at the right), settled.
    func open() async throws -> Fixture {
        var builder = GraphBuilder()
        let first = builder.solid(at: Vector2(40, 40))
        _ = builder.solid(at: Vector2(40, 200))
        let app = try await AppWindow.open(builder.graph, recordsLayout: false)
        app.editor.toggleLibrary()
        try await app.window.runUntilIdle()
        #expect(app.editor.showsLibrary)
        _ = app.steadyWork()
        return Fixture(app: app, node: first.extrude)
    }

    @Test func aSteadyFrameWithTheLibraryAndTheInspectorShownEvaluatesNoPanel() async throws {
        let app = try await open().app
        let steady = app.steadyWork()
        #expect(steady.contentEvaluations == 0, "no panel, canvas layer or node re-evaluates")
        #expect(steady.contentRefusals == 0)
        #expect(steady.retainedIneligible == 0 && steady.retainedRedos == 0, "\(steady.retainedIneligibleReasons)")
    }

    /// Typing in the library's search field changes `libraryQuery`, which only `NodeLibraryView` reads.
    @Test func typingInTheLibraryQueryEvaluatesOnlyTheLibrary() async throws {
        let app = try await open().app
        app.resetWork()
        app.editor.setLibraryQuery("ext")
        app.redraw()
        #expect(app.work.contentEvaluations == 1, "the library, and nothing else")
        #expect(app.editor.libraryItems.count < 20, "the query narrowed the list")
        #expect(app.picture == app.pictureAfterRebuildingEverything(), "the skipped views drew what a full rebuild draws")
    }

    /// Selecting a node changes the inspector's page; the canvas does not read the selection in its panels, only in the two node
    /// views whose outline changed (the old selection and the new).
    @Test func selectingANodeEvaluatesTheInspectorAndTheNodesWhoseSelectionChanged() async throws {
        let fixture = try await open()
        let app = fixture.app
        app.resetWork()
        app.editor.selection = [fixture.node.id]
        app.redraw()
        let work = app.work
        #expect(work.contentEvaluations == 2, "the inspector and the node that gained the selection")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
        app.resetWork()
        app.editor.selection = []
        app.redraw()
        #expect(app.work.contentEvaluations == 2, "the inspector and the node that lost the selection")
    }

    /// A pan changes the transform `CanvasSurface` reads. `DocumentModel` holds the canvas offset and zoom apart from the dock
    /// and `showsLibrary`, so a pan writes only the transform and `GraphPanelBody`, which reads those two, skips: the body, the
    /// library, the inspector, `GraphCanvas` and the nodes (positioned in canvas space) are skipped.
    @Test func panningEvaluatesOnlyTheSurface() async throws {
        let app = try await open().app
        let before = app.picture
        // The first pan frame is redone by MetalUI (the counters of a redone frame are those of the second attempt), so it is
        // taken as warm-up and the next one is counted.
        app.editor.transform = CanvasTransform(offset: Vector2(-3, -2), zoom: 1)
        app.redraw()
        app.resetWork()
        app.editor.transform = CanvasTransform(offset: Vector2(-6, -4), zoom: 1)
        app.redraw()
        #expect(app.work.retainedRedos == 0)
        #expect(app.work.contentEvaluations == 1, "the surface, which reads the transform, and nothing else")
        #expect(app.picture != before, "the canvas moved")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
    }
}
