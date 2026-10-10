import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// Every node on the canvas draws, even when two node IDs print alike. MetalUI's `ForEach` names each element by its
/// id's description and drops a later element whose name repeats (MetalUI `DD-L`, docs/metalui-gaps.md M7-a), and a
/// `NodeID` prints only its UUID's first 8 hex digits, so the canvas keys nodes by the whole UUID.
@MainActor
struct CanvasIdentityRenderTests {
    @Test func nodesWhoseIDsPrintAlikeAllDraw() {
        let nodes = (1...3).map { testNode(RectangleTestNode.self, id: $0, at: Vector2(Double($0 - 1) * 200 + 20, 20)) }
        #expect(Set(nodes.map(\.id.description)).count == 1, "set up: the test IDs print alike")
        let editor = makeEditor(nodes)
        let scene = renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary)
        for node in nodes {
            let origin = canvas.origin + editor.frame(of: node).origin
            let painted = topRect(at: origin + Vector2(40, 60), in: scene).map { screenFrame(of: $0, in: scene) }
            #expect(painted?.origin == origin, "node \(node.id.rawValue): its body paints there")
        }
    }

    @Test func duplicateGhostsWhoseIDsPrintAlikeAllDraw() {
        let nodes = (1...2).map { testNode(RectangleTestNode.self, id: $0, at: Vector2(Double($0 - 1) * 200 + 20, 20)) }
        let editor = makeEditor(nodes)
        editor.selection = [nodeID(1), nodeID(2)]
        let start = editor.screenPoint(in: nodeID(1))
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 200), modifiers: .option)
        #expect(CanvasLayers.ghosts(editor).count == 2)
        let scene = renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary)
        for ghost in CanvasLayers.ghosts(editor) {
            let origin = canvas.origin + editor.frame(of: ghost).origin
            let painted = topRect(at: origin + Vector2(40, 60), in: scene).map { screenFrame(of: $0, in: scene) }
            #expect(painted?.origin == origin, "ghost of \(ghost.id.rawValue): it paints there")
        }
    }
}
