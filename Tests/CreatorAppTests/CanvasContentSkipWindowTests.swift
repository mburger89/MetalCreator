import CreatorGeometry
import CreatorGraph
import CreatorNodes
import CreatorStyle
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The canvas's node, wire and comment views are `.equatable()` (MetalUI C14 slice 1, gap PERF-b): a view whose value is
/// unchanged does not evaluate its `content`. These count that in the app's real window through `FrameWork`'s
/// `contentEvaluations`, `contentSkips` and `contentRefusals` (never milliseconds: the timing re-take is owed, see
/// docs/verification/performance.md), and compare each incremental frame with the picture the window draws when every
/// view evaluates afresh, so a skipped view that should have changed shows as a difference.
@MainActor
struct CanvasContentSkipWindowTests {
    struct Canvas {
        let app: AppWindow
        /// The middle pair, Rectangle → Extrude: the extrude has one wire.
        let middle: (rectangle: Node, extrude: Node)
        let note: StickyNote
        let frame: CommentFrame
    }

    /// Three Rectangle → Extrude pairs under one another (six nodes, three wires), a note and a frame to their right, all
    /// on screen. No Output node, so nothing evaluates and no badge carries a time: two windows draw the same picture.
    func open(themes: ThemeStore = ThemeStore()) async throws -> Canvas {
        var builder = GraphBuilder()
        _ = builder.solid(at: Vector2(40, 40))
        let middle = builder.solid(at: Vector2(40, 200))
        _ = builder.solid(at: Vector2(40, 360))
        var graph = builder.graph
        let note = StickyNote(text: "Note", frame: CanvasRect(origin: Vector2(800, 40), size: Vector2(160, 80)))
        let frame = CommentFrame(title: "Frame", frame: CanvasRect(origin: Vector2(800, 160), size: Vector2(160, 100)))
        graph.stickies[note.id] = note
        graph.frames[frame.id] = frame
        let app = try await AppWindow.open(graph, recordsLayout: false, themes: themes)
        try await app.window.runUntilIdle()
        return Canvas(app: app, middle: middle, note: note, frame: frame)
    }

    /// Presses the middle extrude's header, moves 10 points (past the drag threshold, which selects it) and returns the
    /// pointer's position; the next `mouseDragged` is then a plain move of the node.
    func pressAndMove(_ fixture: Canvas) throws -> Point<Pixels> {
        let app = fixture.app
        let node = try #require(app.editor.graph.nodes[fixture.middle.extrude.id])
        let start = app.point(inCanvas: app.editor.displayOrigin(of: node) + Vector2(20, 10))
        app.window.hover(at: start)
        _ = app.window.send(.mouseDown(MouseEvent(position: start)))
        app.window.tick()
        let moved = Point(x: start.x + Pixels(10), y: start.y)
        _ = app.window.send(.mouseDragged(MouseEvent(position: moved)))
        app.window.tick()
        return moved
    }

    @Test func aSteadyFrameEvaluatesNoCanvasView() async throws {
        let fixture = try await open()
        #expect(fixture.app.editor.drawnNodes.count == 6)
        #expect(fixture.app.editor.drawnNotes.count == 1 && fixture.app.editor.drawnFrames.count == 1)
        let steady = fixture.app.steadyWork()
        #expect(steady.contentEvaluations == 0)
        #expect(steady.contentSkips > 6 + 3 + 2, "every node, wire and comment, and the views inside the nodes, skipped")
        #expect(steady.contentRefusals == 0, "no canvas view reads the environment")
        #expect(fixture.app.picture.count > 100, "the canvas picture holds the nodes")
    }

    /// PERF-b's drag (a): the pointer moves one node; the other five nodes, the comments and the other wires skip.
    @Test func draggingOneNodeEvaluatesOnlyThatNodeAndItsWires() async throws {
        let fixture = try await open()
        let app = fixture.app
        _ = app.steadyWork()
        let from = try pressAndMove(fixture)
        let id = fixture.middle.extrude.id
        let wires = app.editor.graph.links.filter { $0.from.node == id || $0.to.node == id }.count
        #expect(wires == 1)
        app.resetWork()
        _ = app.window.send(.mouseDragged(MouseEvent(position: Point(x: from.x + Pixels(20), y: from.y))))
        app.window.tick()
        let work = app.work
        #expect(app.window.frameWork.count == 1, "one pointer move, one frame")
        #expect(work.contentEvaluations == 1 + wires, "the dragged node's view and its wires' views")
        // Not tied to MetalUI's exact visit count: C14-b (retained subtrees) is expected to change how many inner views a
        // skipped node still visits. What matters is that every other node, wire and comment skipped.
        #expect(work.contentSkips >= (6 - 1) + (3 - wires) + 2, "every other node, wire and comment skipped")
        #expect(work.contentRefusals == 0)
        #expect(app.picture == app.pictureAfterRebuildingEverything(), "the skipped views drew what a full rebuild draws")
    }

    @Test func aThemeChangeEvaluatesEveryViewAndDrawsTheNewColours() async throws {
        let fixture = try await open()
        let app = fixture.app
        _ = app.steadyWork()
        let dracula = app.picture
        app.resetWork()
        app.model.themes.select("alucard")
        app.redraw()
        let work = app.work
        #expect(work.contentSkips == 0 && work.contentEvaluations > 6 + 3 + 2, "every view carries the palette")
        #expect(app.picture != dracula)
        let alucard = ThemeStore()
        alucard.select("alucard")
        let reference = try await open(themes: alucard)
        #expect(app.picture == reference.app.picture, "the same picture as a window that started in the theme")
    }

    /// Selecting another node changes the outline and the glow of two nodes (the old selection and the new) and nothing else.
    @Test func aSelectionChangeEvaluatesOnlyTheNodesWhoseSelectionChanged() async throws {
        let fixture = try await open()
        let app = fixture.app
        _ = app.steadyWork()
        app.editor.selection = [fixture.middle.rectangle.id]
        app.redraw()
        app.resetWork()
        app.editor.selection = [fixture.middle.extrude.id]
        app.redraw()
        let work = app.work
        #expect(work.contentEvaluations == 2, "the node that lost the selection and the one that gained it")
        #expect(work.contentSkips >= (6 - 2) + 3 + 2, "every other node, wire and comment skipped (not tied to MetalUI's visit count)")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
        app.resetWork()
        app.editor.selection = []
        app.redraw()
        #expect(app.work.contentEvaluations == 1, "clearing the selection re-evaluates the one selected node")
    }

    @Test func selectingACommentEvaluatesOnlyThatComment() async throws {
        let fixture = try await open()
        let app = fixture.app
        _ = app.steadyWork()
        app.resetWork()
        app.editor.canvasSelection.comments = [fixture.note.id]
        app.redraw()
        #expect(app.work.contentEvaluations == 1, "the note, whose ring and handle change")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
        app.resetWork()
        app.editor.canvasSelection.comments = [fixture.frame.id]
        app.redraw()
        #expect(app.work.contentEvaluations == 2, "the note lost the selection, the frame gained it")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
    }

    /// A node's badge follows its evaluation: wiring a Rectangle into an Extrude evaluates both, and the views that show
    /// their state, their rows and the new wire re-evaluate with them.
    @Test func aNodesBadgeFollowsItsEvaluationState() async throws {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let extrude = builder.add(ExtrudeNode.self, at: Vector2(300, 40))
        let output = builder.add(OutputNode.self, at: Vector2(560, 40))
        builder.wire(extrude, "solid", to: output, "solid")
        let app = try await AppWindow.open(builder.graph, recordsLayout: false)
        try await app.window.runUntilIdle()
        let before = app.editor.result(of: extrude.id)?.state
        let glyphs = app.window.scene.glyphs.count
        app.resetWork()
        app.editor.connect(Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: extrude.id, socket: "profile")))
        await app.model.settle()
        try await app.window.runUntilIdle()
        let after = try #require(app.editor.result(of: extrude.id)?.state)
        #expect(before != after && after.isSuccess, "the Extrude evaluated")
        #expect(app.work.contentEvaluations >= 3, "the Rectangle, the Extrude and the new wire")
        #expect(app.window.scene.glyphs.count > glyphs, "the badge shows the time it took")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
    }
}
