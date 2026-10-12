import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Typing a frame's title on the canvas through the app's real window (human checks CT-3 and CT-5): a one-line field
/// over the title bar, Return commits (`onSubmit`), Esc cancels, a press elsewhere commits.
@MainActor
struct CanvasTitleTypingWindowTests {
    let fixture = TypingFixture()

    @Test(arguments: [DockSide.bottom, .left])
    func aDoubleClickOnTheTitleBarOpensAFocusedOneLineField(dock: DockSide) async throws {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.kind == .frameTitle)
        let field = try #require(try app.window.focusedElement)
        #expect(field.role == .textField)
        #expect(field.value == "Bracket")
        let rect = try #require(app.editor.frame(ofComment: fixture.box.id))
        let corner = app.point(inCanvas: rect.origin)
        #expect(abs(field.frame.origin.x.value - corner.x.value) <= 1 && abs(field.frame.origin.y.value - corner.y.value) <= 1,
                "the field starts at the title bar's corner, give or take the field's own inset of a point")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func returnCommitsTheTitleAsOneUndoStep(dock: DockSide) async throws {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeKey(.delete)
        app.window.typeText("Front plate")
        app.window.typeKey(.return)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title.contains("Front plate") == true)
        #expect(app.editor.document.undoName == "Edit Frame")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func escapeCancelsTheTitle(dock: DockSide) async throws {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeText("Gone")
        app.window.typeKey(.escape)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
    }

    @Test func aClickAwayCommitsTheTitle() async throws {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeText("Front ")
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title.contains("Front") == true)
    }

    /// Human check CT-3: the title bar still drags the frame, with the nodes inside it, as one undo step.
    @Test func draggingTheTitleBarMovesTheFrameAndItsNodesAsOneUndoStep() async throws {
        var builder = GraphBuilder()
        let inside = builder.add(RectangleNode.self, at: Vector2(300, 90))
        var graph = builder.graph
        graph.frames = [fixture.box.id: fixture.box]
        let app = try await AppWindow.open(graph)
        let start = app.titleBarCentre(ofFrame: fixture.box.id)
        app.window.drag(from: start, to: Point(x: start.x + Pixels(50), y: start.y + Pixels(30)), steps: 6)
        #expect(app.editor.commentEdit == nil, "a drag edits nothing")
        #expect(app.editor.graph.frames[fixture.box.id]?.frame.origin == Vector2(310, 70))
        #expect(app.editor.graph.nodes[inside.id]?.position == Vector2(350, 120), "the node inside moved with it")
        #expect(app.editor.document.undoName == "Move")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.frame.origin == Vector2(260, 40))
        #expect(app.editor.graph.nodes[inside.id]?.position == Vector2(300, 90))
        #expect(!app.editor.document.canUndo, "one step")
    }

    @Test func aBlankTitleIsRefusedAndTheOldOneStays() async throws {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeKey(.delete)
        #expect(app.editor.commentEdit?.draft == "")
        app.window.typeKey(.return)
        #expect(app.editor.refusal?.message == "A frame needs a title.")
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
        #expect(app.editor.commentEdit == nil)
    }
}
