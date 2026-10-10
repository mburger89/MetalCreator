import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct EditingTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
    let output = testNode(OutputTestNode.self, id: 3, at: Vector2(600, 0))

    func chain() -> EditorModel {
        makeEditor([rect, extrude, output], [wire(rect, "profile", extrude, "profile"), wire(extrude, "solid", output, "solid")])
    }

    @Test func deleteRemovesNodesAndTheirWiresAndUndoRestoresThem() {
        let editor = chain()
        let before = editor.graph
        editor.selection = [extrude.id]
        editor.deleteSelection()
        #expect(editor.graph.nodes.count == 2)
        #expect(editor.graph.links.isEmpty)
        #expect(editor.selection.isEmpty)
        editor.document.undo()
        #expect(editor.graph == before)
    }

    @Test func deleteWithNothingSelectedDoesNothing() {
        let editor = chain()
        editor.deleteSelection()
        #expect(!editor.document.canUndo)
    }

    @Test func copyPasteKeepsInternalWiresOnlyAndOffsetsFurtherEachTime() {
        let editor = chain()
        editor.selection = [rect.id, extrude.id]
        editor.copySelection()
        editor.paste()
        let first = editor.selection
        #expect(first.count == 2)
        #expect(first.isDisjoint(with: [rect.id, extrude.id]))
        let firstCopies = first.compactMap { editor.graph.nodes[$0] }
        #expect(Set(firstCopies.map(\.position)) == [Vector2(24, 24), Vector2(324, 24)])
        // The rectangle → extrude wire is copied; extrude → output is not, as output wasn't copied.
        let copiedLinks = editor.graph.links.filter { first.contains($0.to.node) }
        #expect(copiedLinks.count == 1)
        #expect(copiedLinks.allSatisfy { first.contains($0.from.node) })
        editor.paste()
        let secondCopies = editor.selection.compactMap { editor.graph.nodes[$0] }
        #expect(Set(secondCopies.map(\.position)) == [Vector2(48, 48), Vector2(348, 48)])
        editor.document.undo()
        editor.document.undo()
        #expect(editor.graph.nodes.count == 3)
    }

    @Test func pasteWithAnEmptyClipboardDoesNothing() {
        let editor = chain()
        editor.paste()
        #expect(!editor.document.canUndo)
    }

    @Test func duplicateLeavesTheClipboardAlone() {
        let editor = chain()
        editor.selection = [output.id]
        editor.copySelection()
        editor.selection = [rect.id]
        editor.duplicateSelection()
        #expect(editor.clipboard?.nodes.map(\.id) == [output.id])
        let copy = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        #expect(copy?.typeID == RectangleTestNode.typeID)
        #expect(copy?.position == Vector2(24, 24))
    }

    @Test func copiesKeepTheirInputValues() {
        let number = testNode(NumberTestNode.self, id: 9, at: .zero, values: ["value": .number(42)])
        let editor = makeEditor([number])
        editor.selection = [number.id]
        editor.duplicateSelection()
        let copy = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        #expect(copy?.inputValues["value"] == .number(42))
    }

    @Test func addNodeLandsUnderTheScreenPointInStoredCoordinates() {
        let editor = makeEditor([], dock: .left)
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        editor.addNode(NumberTestNode.typeID, atScreen: Vector2(110, 60))
        let added = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        // Screen (110, 60) is display canvas (50, 20); the vertical flow stores its transpose.
        #expect(added?.position == Vector2(20, 50))
        #expect(added?.name == "Number")
        #expect(added?.isOutput == false)
        // `NodeRegistry.makeNode` flags `.output`-category nodes (M3), so the palette needs no special case.
        editor.addNode(OutputTestNode.typeID, atScreen: Vector2(110, 60))
        #expect(editor.selection.first.flatMap { editor.graph.nodes[$0] }?.isOutput == true)
    }

    @Test func connectReplacesTheOccupiedInputInOneUndoStep() {
        let other = testNode(RectangleTestNode.self, id: 4, at: Vector2(0, 300))
        let editor = makeEditor([rect, other, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.connect(wire(other, "profile", extrude, "profile"))
        #expect(editor.graph.links == [wire(other, "profile", extrude, "profile")])
        editor.document.undo()
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
    }

    @Test func aRefusedConnectionChangesNothingAndSaysWhy() {
        let number = testNode(NumberTestNode.self, id: 4, at: Vector2(0, 300))
        let editor = makeEditor([number, extrude])
        editor.connect(wire(number, "value", extrude, "profile"))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal == RefusalFeedback(message: "A number can't connect to a profile input.", node: extrude.id, serial: 1))
        #expect(editor.shakeCount(of: extrude.id) == 1)
        #expect(!editor.document.canUndo)
    }

    @Test func reconnectingAnExistingWireAddsNoUndoStep() {
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.connect(wire(rect, "profile", extrude, "profile"))
        #expect(!editor.document.canUndo)
    }

    @Test func connectionProblemMessagesArePlain() {
        #expect(ConnectionProblem.sameNode.message == "A node can't be wired to itself.")
        #expect(ConnectionProblem.typeMismatch(from: .solid, to: .edgeSet).message == "A solid can't connect to an edge set input.")
        #expect(ConnectionProblem.unknownNode.message == "That node's type isn't available, so it can't be wired.")
    }
}
