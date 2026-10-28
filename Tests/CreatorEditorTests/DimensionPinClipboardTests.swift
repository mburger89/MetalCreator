import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Pins on the clipboard (DIM-3 Task 3): copying a node takes its pins, a paste puts them on the copy in the paste's one undo
/// step, and a pin of a node that was not copied stays behind.
@MainActor
struct DimensionPinClipboardTests {
    let scene = TieScene()

    var pinA1: DimensionPin { DimensionPin(node: scene.a1.id, target: .input("value")) }
    var pinB1: DimensionPin { DimensionPin(node: scene.b1.id, target: .input("value")) }

    func editor(pins: [DimensionPin]) throws -> EditorModel {
        let editor = scene.editor()
        for pin in pins { try editor.document.perform(.pinDimension(pin), name: UndoName.pinDimension) }
        return editor
    }

    @Test func copyAndPasteCarryAPinToTheCopy() async throws {
        let editor = try editor(pins: [pinA1])
        editor.selection = [scene.a1.id]
        editor.copySelection()
        editor.paste()
        let copy = try #require(editor.canvasSelection.nodes.first)
        #expect(copy != scene.a1.id)
        #expect(editor.graph.dimensionPins.count == 2)
        #expect(Set(editor.graph.dimensionPins) == [pinA1, DimensionPin(node: copy, target: .input("value"))])
        #expect(editor.document.undoName == UndoName.paste)
        editor.perform(.undo)
        #expect(editor.graph.dimensionPins == [pinA1], "one undo step takes the copy and its pin")
        #expect(editor.graph.nodes.count == 6)
    }

    @Test func aPinOfANodeNotCopiedStaysBehind() async throws {
        let editor = try editor(pins: [pinA1, pinB1])
        editor.selection = [scene.a1.id]
        editor.copySelection()
        #expect(editor.clipboard?.dimensionPins == [pinA1])
        editor.paste()
        let copy = try #require(editor.canvasSelection.nodes.first)
        #expect(editor.graph.dimensionPins.count == 3)
        #expect(editor.graph.dimensionPins.filter { $0.node == copy } == [DimensionPin(node: copy, target: .input("value"))])
        #expect(editor.graph.dimensionPins.filter { $0.node == scene.b1.id } == [pinB1], "b1 was not copied and has no copy")
    }
}
