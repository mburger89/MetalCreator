import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// A node with a board file control, standing in for Import KiCad Board.
private enum BoardFileTestNode: NodeDefinition {
    static let typeID = "editortest.boardFile"
    static let displayName = "Board File"
    static let category = NodeCategory.solid
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("number", .number)]
    static let inspector = [InspectorSection(title: "File", controls: [.pcbFile(NodeSetting.pcbFile)])]
    static let factsTitle = "Board"
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var outputs = NodeOutputs(["number": .number(1)])
        outputs.facts = [PayloadFact("Size", "100 × 80 mm"), PayloadFact("Holes", "4")]
        return outputs
    }
}

/// Import KiCad Board's file rows (a board is linked, never embedded) and its facts section.
@MainActor
struct PCBFileRowsTests {
    let registry = NodeRegistry([BoardFileTestNode.self])

    func editor(_ reference: ImageReference?) -> (EditorModel, Node) {
        var node = registry.makeNode(BoardFileTestNode.typeID)
        node.isOutput = true
        if let reference { node.inputValues[NodeSetting.pcbFile] = .pcbFile(reference) }
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        return (editor, node)
    }

    @Test func eachStateShowsItsRowsAndButtons() {
        #expect(editor(nil).0.inspectorPage.sections.first?.rows == [
            .readOnly(label: "File", text: "No file chosen"),
            .button(title: "Choose File…", action: .choosePCBFile),
        ])
        let linked = ImageReference.linked(relativePath: nil, absolutePath: "/tmp/board.kicad_pcb")
        #expect(editor(linked).0.inspectorPage.sections.first?.rows == [
            .readOnly(label: "File", text: "Linked · board.kicad_pcb"),
            .button(title: "Relink…", action: .relinkPCBFile),
        ])
    }

    @Test func aBoardIsNeverOfferedEmbedding() {
        let hash = ImageHash(of: Data("a board".utf8))
        let rows = editor(.embedded(hash)).0.inspectorPage.sections.first?.rows ?? []
        let actions = rows.compactMap { row -> InspectorAction? in if case .button(_, let action) = row { action } else { nil } }
        #expect(actions == [.choosePCBFile])
        #expect(rows.first == .readOnly(label: "File", text: "No file chosen"))
    }

    @Test func theUndoNamesAreFixedSentences() {
        #expect([UndoName.importKiCadBoard, UndoName.chooseBoardFile, UndoName.relinkBoardFile]
            == ["Import KiCad Board", "Choose Board File", "Relink Board File"])
    }

    @Test func pressingABoardButtonIsRecordedForTheAppShell() {
        let (editor, node) = editor(nil)
        for action in [InspectorAction.choosePCBFile, .relinkPCBFile] {
            editor.press(action, on: node.id)
            #expect(editor.inspectorRequest?.action == action)
        }
    }

    @Test func factsFollowTheDeclaredSectionsUnderTheNodesTitle() async {
        let (editor, _) = editor(nil)
        #expect(editor.inspectorPage.sections.map(\.title) == ["File"], "no result yet, no facts")
        await editor.document.waitForEvaluation()
        let sections = editor.inspectorPage.sections
        #expect(sections.map(\.title) == ["File", "Board"])
        #expect(sections.last?.rows == [.readOnly(label: "Size", text: "100 × 80 mm"), .readOnly(label: "Holes", text: "4")])
    }
}
