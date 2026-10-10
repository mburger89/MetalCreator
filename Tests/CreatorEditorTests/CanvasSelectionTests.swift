import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The selection model every gesture and key goes through (spec 2026-10-09 §3), and the one sub-project B extends.
@MainActor
struct CanvasSelectionTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
    let c = testNode(NumberTestNode.self, id: 3, at: Vector2(600, 0))

    @Test func theModesReplaceAddAndToggle() {
        let ab = CanvasSelection(nodes: [a.id, b.id]), bc = CanvasSelection(nodes: [b.id, c.id])
        #expect(ab.applying(bc, mode: .replace) == bc)
        #expect(ab.applying(bc, mode: .add) == CanvasSelection(nodes: [a.id, b.id, c.id]))
        #expect(ab.applying(bc, mode: .toggle) == CanvasSelection(nodes: [a.id, c.id]))
        #expect(ab.isSuperset(of: CanvasSelection(nodes: [b.id])) && !ab.isSuperset(of: bc))
        #expect(CanvasSelection().isEmpty && !ab.isEmpty)
    }

    @Test func theModifiersPickTheMode() {
        #expect(SelectionMode([]) == .replace)
        #expect(SelectionMode(.option) == .replace, "⌥ duplicates; it isn't a selection mode")
        #expect(SelectionMode(.shift) == .add)
        #expect(SelectionMode(.command) == .toggle)
        #expect(SelectionMode([.command, .shift]) == .toggle, "⌘ wins over ⇧")
    }

    @Test func settingTheNodeSelectionReplacesTheWholeSelection() {
        let editor = makeEditor([a, b])
        editor.select(CanvasSelection(nodes: [a.id]), mode: .add)
        #expect(editor.selection == [a.id])
        editor.selection = [b.id]
        #expect(editor.canvasSelection == CanvasSelection(nodes: [b.id]))
        editor.select(CanvasSelection(nodes: [a.id]), mode: .toggle)
        #expect(editor.selection == [a.id, b.id])
    }

    @Test func selectAllAndClear() {
        let editor = makeEditor([a, b, c])
        editor.selectAll()
        #expect(editor.selection == [a.id, b.id, c.id])
        #expect(editor.allItems == editor.canvasSelection)
        editor.clearSelection()
        #expect(editor.canvasSelection.isEmpty)
    }

    @Test func aHitSelectsItsNode() {
        let editor = makeEditor([a, b])
        let socket = SocketRef(Endpoint(node: b.id, socket: "value"), isInput: true)
        #expect(editor.items(for: .node(a.id)) == CanvasSelection(nodes: [a.id]))
        #expect(editor.items(for: .socket(socket)) == CanvasSelection(nodes: [b.id]))
        #expect(editor.items(for: .empty) == nil)
        #expect(editor.items(intersecting: CanvasRect(corner: Vector2(150, 10), Vector2(320, 20))) == CanvasSelection(nodes: [a.id, b.id]))
    }

    /// Undo never prunes the selection, so it can name nodes no longer on the canvas; they are skipped.
    @Test func positionsAndMovesSkipItemsNoLongerOnTheCanvas() {
        let editor = makeEditor([a, b])
        let start = editor.positions(of: CanvasSelection(nodes: [a.id, b.id, nodeID(9)]))
        #expect(start == SelectionPositions(nodes: [a.id: .zero, b.id: Vector2(300, 0)]))
        #expect(start.items == CanvasSelection(nodes: [a.id, b.id]))
        #expect(editor.moveCommands(from: start, by: Vector2(5, 7))
            == [.move(a.id, to: Vector2(5, 7)), .move(b.id, to: Vector2(305, 7))])
        #expect(editor.positions(of: CanvasSelection(nodes: [nodeID(9)])).isEmpty)
    }

    @Test func boundsCoverTheItemsDrawnFrames() {
        let editor = makeEditor([a, c])
        let size = NodeLayout.size(editor.shape(of: a))
        #expect(editor.bounds(of: CanvasSelection(nodes: [a.id, c.id])) == CanvasRect(origin: .zero, size: Vector2(600 + size.x, size.y)))
        #expect(editor.bounds(of: CanvasSelection(nodes: [c.id])) == editor.frame(of: c))
        #expect(editor.bounds(of: CanvasSelection()) == nil)
        #expect(editor.bounds(of: CanvasSelection(nodes: [nodeID(9)])) == nil)
    }

    @Test func boundsAreInDisplayPointsInTheLeftDock() {
        let editor = makeEditor([a, c], dock: .left)
        let size = NodeLayout.size(editor.shape(of: a))
        // The left dock draws the transpose: c's stored (600, 0) is drawn at (0, 600).
        #expect(editor.bounds(of: CanvasSelection(nodes: [a.id, c.id])) == CanvasRect(origin: .zero, size: Vector2(size.x, 600 + size.y)))
    }

    /// Spec §3: "Selected items draw last and are hit-tested in the same order (existing rule)", pinned for several.
    @Test func selectedNodesDrawLastAndAreHitFirst() {
        let back = testNode(NumberTestNode.self, id: 1, at: .zero)
        let middle = testNode(NumberTestNode.self, id: 2, at: Vector2(10, 10))
        let front = testNode(NumberTestNode.self, id: 3, at: Vector2(20, 20))
        let editor = makeEditor([back, middle, front])
        let overlap = Vector2(100, 60)
        #expect(editor.hitTest(overlap) == .node(front.id))
        editor.selection = [back.id, middle.id]
        #expect(editor.drawOrder.map(\.id) == [front.id, back.id, middle.id])
        #expect(editor.hitTest(overlap) == .node(middle.id))
        editor.selection = [back.id]
        #expect(editor.hitTest(overlap) == .node(back.id))
    }
}
