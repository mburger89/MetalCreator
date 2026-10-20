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
        // MetalUI C14b-2 (record §110): an unchanged outermost `.equatable()` occurrence skips its whole build recursion and
        // its layout rows are grafted, so the views inside it are no longer visited, let alone counted as skips. Since the
        // panels are `.equatable()` too (C14-d, `PanelContentSkipWindowTests`), the outermost occurrences of a steady frame are
        // the graph panel's body (which holds the canvas, its nodes, wires and comments) and the inspector: two grafts. The
        // `GraphPanel(...)` call itself is not `.equatable()` (its `onGeometryChange` made it ineligible every frame).
        #expect(steady.contentSkips >= 2, "the body and the inspector skipped")
        #expect(steady.retainedGrafts == 2, "each was grafted, not built")
        #expect(steady.retainedGraftIneligible == 0 && steady.retainedRedos == 0, "no graft refused, no frame redone")
        // MetalUI C14b-3 (record §121): reading control state is not a write, so nothing in a steady frame is ineligible.
        #expect(steady.retainedIneligible == 0, "no replay ineligible")
        #expect(steady.retainedIneligibleReasons.isEmpty, "nothing recorded: \(steady.retainedIneligibleReasons)")
        #expect(steady.retainedSkippedRequests > 0, "the grafts stood for element requests the build did not make")
        #expect(steady.contentRefusals == 0, "no canvas view reads the environment")
        #expect(fixture.app.picture.count > 100, "the canvas picture holds the nodes")
    }

    /// A warm pan (C14-d): the canvas transform changes and nothing a node view holds does, so no node, wire or comment view
    /// evaluates (their positions are in canvas space; the surface applies the pan as a render effect). The surface, which
    /// reads the transform, is the one evaluation, and the incremental picture is the one a full rebuild draws.
    @Test func aWarmPanEvaluatesNoNodeView() async throws {
        let fixture = try await open()
        let app = fixture.app
        let before = app.picture
        // The first pan frame is redone by MetalUI (the counters of a redone frame are those of the second attempt): warm-up.
        app.editor.transform = CanvasTransform(offset: Vector2(-3, -2), zoom: 1)
        app.redraw()
        for step in 2...4 {
            app.resetWork()
            app.editor.transform = CanvasTransform(offset: Vector2(-3 * Double(step), -2 * Double(step)), zoom: 1)
            app.redraw()
            #expect(app.editor.drawnNodes.count == 6, "the pan kept every node on screen")
            #expect(app.work.contentEvaluations == 1, "step \(step): the surface alone, no node, wire or comment view")
            #expect(app.work.contentRefusals == 0 && app.work.retainedRedos == 0)
        }
        #expect(app.picture != before, "the canvas moved")
        #expect(app.picture == app.pictureAfterRebuildingEverything(), "the retained nodes drew what a full rebuild draws")
    }

    /// One node moves, and it has no wires: exactly that node's view evaluates (its origin changed; the views inside it hold the
    /// same values, so they skip) and the other three nodes skip. The one other evaluation is the inspector, which reads the
    /// graph the edit changed (a batch of two moves counts 3: the constant is the inspector, one more per node).
    @Test func changingOneNodeEvaluatesExactlyThatNodeView() async throws {
        var builder = GraphBuilder()
        let nodes = (0..<4).map { builder.add(RectangleNode.self, at: Vector2(40, 40 + 120 * Double($0))) }
        let app = try await AppWindow.open(builder.graph, recordsLayout: false)
        try await app.window.runUntilIdle()
        #expect(app.editor.drawnNodes.count == 4)
        _ = app.steadyWork()
        // The first frame after an edit may be redone by MetalUI (the counters of a redone frame are those of the second
        // attempt): a first move is the warm-up and the second is counted.
        try app.editor.edit(.move(nodes[1].id, to: Vector2(290, 160)), name: "Move")
        try await app.window.runUntilIdle()
        app.resetWork()
        try app.editor.edit(.move(nodes[1].id, to: Vector2(300, 160)), name: "Move")
        try await app.window.runUntilIdle()
        let work = app.work
        #expect(work.contentEvaluations == 1 + 1, "the moved node's view and the inspector, nothing else")
        #expect(work.contentRefusals == 0)
        #expect(work.contentSkips >= 3, "the other three nodes skipped")
        #expect(app.picture == app.pictureAfterRebuildingEverything(), "the skipped views drew what a full rebuild draws")
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
        #expect(work.contentEvaluations == 1 + wires + 1,
                "the dragged node's view, its wires' views and the inspector (the drag selects it)")
        // Not tied to MetalUI's exact visit count: C14b-2 skips a skipped node's whole build recursion, so its inner views
        // are no longer visited. What matters is that every other node, wire and comment skipped.
        #expect(work.contentSkips >= (6 - 1) + (3 - wires) + 2, "every other node, wire and comment skipped")
        #expect(work.contentRefusals == 0)
        #expect(app.picture == app.pictureAfterRebuildingEverything(), "the skipped views drew what a full rebuild draws")
    }

    /// A wire's value is its geometry and one colour, no `Palette`: only a window built afresh on the moved graph tells a
    /// wire skipped while its endpoint moved from one drawn right.
    @Test func aWireFollowsItsMovedEndpointAndDrawsWhatAFreshWindowDraws() async throws {
        let fixture = try await open()
        let app = fixture.app
        _ = app.steadyWork()
        let from = try pressAndMove(fixture)
        let moved = Point(x: from.x + Pixels(60), y: from.y + Pixels(40))
        _ = app.window.send(.mouseDragged(MouseEvent(position: moved)))
        app.window.tick()
        _ = app.window.send(.mouseUp(MouseEvent(position: moved)))
        app.window.tick()
        app.editor.selection = []
        app.redraw()
        let node = try #require(app.editor.graph.nodes[fixture.middle.extrude.id])
        #expect(node.position != fixture.middle.extrude.position, "the extrude moved, and so did its wire's end")
        let fresh = try await AppWindow.open(app.editor.graph, recordsLayout: false)
        try await fresh.window.runUntilIdle()
        #expect(app.picture == fresh.picture, "the wire was redrawn to the node's new place")
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
        #expect(work.contentEvaluations > 6 + 3 + 2, "every view carries the palette")
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
        #expect(work.contentEvaluations == 3, "the node that lost the selection, the one that gained it, and the inspector")
        #expect(work.contentSkips >= (6 - 2) + 3 + 2, "every other node, wire and comment skipped (not tied to MetalUI's visit count)")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
        app.resetWork()
        app.editor.selection = []
        app.redraw()
        #expect(app.work.contentEvaluations == 2, "clearing the selection re-evaluates the one selected node and the inspector")
    }

    @Test func selectingACommentEvaluatesOnlyThatComment() async throws {
        let fixture = try await open()
        let app = fixture.app
        _ = app.steadyWork()
        app.resetWork()
        app.editor.canvasSelection.comments = [fixture.note.id]
        app.redraw()
        #expect(app.work.contentEvaluations == 2, "the note, whose ring and handle change, and the inspector")
        #expect(app.picture == app.pictureAfterRebuildingEverything())
        app.resetWork()
        app.editor.canvasSelection.comments = [fixture.frame.id]
        app.redraw()
        #expect(app.work.contentEvaluations == 3, "the note lost the selection, the frame gained it, and the inspector")
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

    /// MetalUI C14-c (environment epoch): the box reads the `ThemeStore` from the environment and is `.equatable()`. A frame
    /// where its rect and the theme it read are unchanged skips and grafts it; a new rect or a new theme evaluates it.
    @Test func theSelectionBoxIsSkippedWhileItsRectAndTheThemeAreUnchanged() async throws {
        let fixture = try await open()
        let app = fixture.app
        let start = app.point(inCanvas: Vector2(500, 60))
        app.window.hover(at: start)
        _ = app.window.send(.mouseDown(MouseEvent(position: start)))
        app.window.tick()
        let moved = Point(x: start.x + Pixels(40), y: start.y + Pixels(30))
        _ = app.window.send(.mouseDragged(MouseEvent(position: moved)))
        app.window.tick()
        guard case .boxSelecting? = app.editor.interaction else {
            Issue.record("expected a box")
            return
        }
        // The first steady frame settles anything still pending; the second is the one measured.
        _ = app.steadyWork()
        let steady = app.steadyWork()
        #expect(steady.contentEvaluations == 0, "the box's rect and the theme it read are unchanged")
        #expect(steady.contentRefusals == 0, "reading the environment no longer refuses .equatable()")
        // While the press is held the body is not grafted as a whole (a gesture is active in it), so each canvas view and the
        // box are grafted on their own, and the inspector too.
        let canvasViews = 6 + 3 + 2 + 1 + 1
        #expect(steady.contentSkips >= canvasViews, "the box is skipped with the other canvas views and the inspector")
        #expect(steady.retainedGrafts == canvasViews, "and grafted, not built")

        app.resetWork()
        _ = app.window.send(.mouseDragged(MouseEvent(position: Point(x: moved.x + Pixels(20), y: moved.y))))
        app.window.tick()
        #expect(app.work.contentEvaluations == 2, "a new rect evaluates the box and the surface, which reads the interaction")
        #expect(app.work.contentRefusals == 0)

        app.resetWork()
        app.model.themes.select("alucard")
        app.redraw()
        // Not `contentSkips == 0`: whether a view that did not read the theme is skipped while others evaluate depends on
        // the platform's frame order (CI: Linux and Windows skipped some). What must hold is that the box is not stale:
        // the picture equals a window that started in the theme and drew the same box.
        #expect(app.work.contentEvaluations > 0, "a theme change reaches the box")
        let alucard = ThemeStore()
        alucard.select("alucard")
        let reference = try await open(themes: alucard)
        let from = reference.app.point(inCanvas: Vector2(500, 60))
        reference.app.window.hover(at: from)
        _ = reference.app.window.send(.mouseDown(MouseEvent(position: from)))
        reference.app.window.tick()
        let first = Point(x: from.x + Pixels(40), y: from.y + Pixels(30))
        _ = reference.app.window.send(.mouseDragged(MouseEvent(position: first)))
        reference.app.window.tick()
        _ = reference.app.window.send(.mouseDragged(MouseEvent(position: Point(x: first.x + Pixels(20), y: first.y))))
        reference.app.window.tick()
        #expect(app.picture == reference.app.picture, "the box is drawn in the new theme, as a fresh window draws it")
    }
}
