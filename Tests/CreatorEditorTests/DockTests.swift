import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

@MainActor
struct DockTests {
    @Test func theDockIsSavedWithTheDocument() throws {
        let editor = makeEditor([])
        editor.setDock(.left)
        editor.transform = CanvasTransform(offset: Vector2(3, 4), zoom: 1.5)
        let file = try JSONDecoder().decode(GraphFile.self, from: try editor.document.fileData())
        #expect(file.viewState == ViewState(dock: .left, canvasOffset: Vector2(3, 4), canvasZoom: 1.5))
    }

    @Test func showingAHiddenPanelReturnsItToItsLastSide() {
        let editor = makeEditor([], dock: .bottom)
        editor.toggleHidden()
        #expect(editor.dock == .hidden)
        #expect(!editor.isPanelVisible)
        editor.toggleHidden()
        #expect(editor.dock == .bottom)
    }

    @Test func aDocumentSavedHiddenShowsOnTheLeft() {
        let editor = makeEditor([], dock: .hidden)
        editor.toggleHidden()
        #expect(editor.dock == .left)
    }

    @Test func switchingDocksKeepsStoredPositionsAndTransposesTheDrawing() {
        let node = testNode(NumberTestNode.self, id: 1, at: Vector2(250, 40))
        let editor = makeEditor([node], dock: .bottom)
        #expect(editor.frame(of: node).origin == Vector2(250, 40))
        editor.setDock(.left)
        #expect(editor.graph.nodes[node.id]?.position == Vector2(250, 40))
        #expect(editor.frame(of: node).origin == Vector2(40, 250))
        #expect(!editor.document.canUndo)
    }
}
