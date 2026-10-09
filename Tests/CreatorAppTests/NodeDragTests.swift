import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// Dragging a node on the graph canvas changes only its position (spec §4.5: a move doesn't affect results). The
/// app must not re-evaluate, send the viewport a new scene or new handles, or change what the viewport draws, so a
/// drag costs one window frame per pointer move and nothing more (measured in docs/metalui-gaps.md, PERF-a/b).
@MainActor
struct NodeDragTests {
    @Test func draggingANodeLeavesTheEvaluationAndTheViewportAlone() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        let editor = app.editor
        let node = try #require(editor.graph.nodes[box.extrude.id])
        let start = editor.transform.toScreen(editor.displayOrigin(of: node) + Vector2(20, 10))
        // The first move past the drag threshold selects the node, which shows its handles: that settles first.
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(4, 4))
        await app.settle()
        #expect(editor.selection == [box.extrude.id])
        let renderKey = app.viewport.renderKey
        let handles = app.viewport.handles
        let solids = app.viewport.items.map { ObjectIdentifier($0.solid) }
        let states = app.document.results.mapValues(\.state)
        #expect(!solids.isEmpty, "the Output's solid is shown")

        for step in 1...30 {
            editor.pointerDragged(from: start, to: start + Vector2(4 + Double(step) * 3, 4 + Double(step)))
            #expect(!app.document.isEvaluating, "step \(step) scheduled an evaluation")
            await app.settle()
            #expect(app.viewport.renderKey == renderKey, "step \(step) changed what the viewport draws")
            #expect(app.viewport.handles == handles)
            #expect(app.viewport.items.map { ObjectIdentifier($0.solid) } == solids, "step \(step) re-sent the scene")
            #expect(app.document.results.mapValues(\.state) == states)
        }
        editor.pointerReleased(from: start, at: start + Vector2(94, 34))
        let moved = try #require(app.document.graph.nodes[box.extrude.id])
        #expect(moved.position != node.position)
        app.document.undo()
        #expect(app.document.graph.nodes[box.extrude.id]?.position == node.position, "the drag is one undo step")
    }
}
