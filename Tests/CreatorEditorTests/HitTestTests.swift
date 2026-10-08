import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct HitTestTests {
    @Test func hitsANodeUnderAZoomedAndPannedCanvas() {
        let number = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 50))
        let editor = makeEditor([number])
        editor.transform = CanvasTransform(offset: Vector2(-40, 30), zoom: 2)
        // Canvas (110, 60) is inside the node (origin 100, 50) → screen (180, 150).
        #expect(editor.hitTest(Vector2(180, 150)) == .node(number.id))
        // Canvas (95, 60) is left of it → screen (150, 150).
        #expect(editor.hitTest(Vector2(150, 150)) == .empty)
    }

    @Test func socketHitRadiusIsInScreenPoints() {
        let number = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([number])
        editor.transform = CanvasTransform(zoom: 3)
        let socket = editor.screenPoint(of: number.id, "value", input: false)
        let expected = CanvasHit.socket(SocketRef(Endpoint(node: number.id, socket: "value"), isInput: false))
        #expect(editor.hitTest(socket + Vector2(8, 0)) == expected)
        #expect(editor.hitTest(socket + Vector2(0, 10)) != expected)
    }

    @Test func theFrontmostNodeWinsAndSelectionIsRaised() {
        let back = testNode(NumberTestNode.self, id: 1, at: .zero)
        let front = testNode(NumberTestNode.self, id: 2, at: Vector2(10, 10))
        let editor = makeEditor([back, front])
        let overlap = Vector2(40, 30)
        #expect(editor.hitTest(overlap) == .node(front.id))
        editor.selection = [back.id]
        #expect(editor.hitTest(overlap) == .node(back.id))
        #expect(editor.drawOrder.map(\.id) == [front.id, back.id])
    }

    @Test func leftDockHitsTheTransposedPosition() {
        let number = testNode(NumberTestNode.self, id: 1, at: Vector2(300, 0))
        let editor = makeEditor([number], dock: .left)
        #expect(editor.hitTest(Vector2(10, 310)) == .node(number.id))
        #expect(editor.hitTest(Vector2(310, 10)) == .empty)
        // In the vertical flow the output sits on the bottom edge.
        let output = editor.screenPoint(of: number.id, "value", input: false)
        #expect(output == Vector2(84, 300 + NodeLayout.size(editor.shape(of: number)).y))
    }

    @Test func boxSelectionFindsIntersectingFrames() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))
        let editor = makeEditor([a, b])
        #expect(editor.nodes(intersecting: CanvasRect(corner: Vector2(150, 10), Vector2(200, 20))) == [a.id])
        #expect(editor.nodes(intersecting: CanvasRect(corner: Vector2(-10, -10), Vector2(500, 20))) == [a.id, b.id])
    }
}
