import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// Typing a Cull Pattern mask or a Cull Index list is one named undo step, like any text setting (`TextSettingTests`).
@MainActor
struct VariationSettingTests {
    /// Types `text` into the first text field of a new `typeID` node and returns the editor and the node.
    func type(_ text: String, into typeID: String) throws -> (editor: EditorModel, node: Node) {
        let node = BuiltInNodes.registry.makeNode(typeID)
        let editor = makeEditor([node], registry: BuiltInNodes.registry)
        editor.selection = [node.id]
        let field = try #require(editor.inspectorPage.sections.flatMap(\.rows).compactMap { row -> InputField? in
            if case .text(let field) = row { field } else { nil }
        }.first)
        editor.setInput(field, to: .text(text))
        return (editor, node)
    }

    @Test func typingACullPatternMaskIsOneNamedUndoStep() throws {
        let (editor, node) = try type("1 1 0", into: CullPatternNode.typeID)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullPattern] == .text("1 1 0"))
        #expect(editor.document.undoName == "Change Cull pattern")
        editor.document.undo()
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullPattern] == .text("1 0"))
    }

    @Test func typingCullIndicesIsOneNamedUndoStep() throws {
        let (editor, node) = try type("1, {0;3}", into: CullIndexNode.typeID)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullIndices] == .text("1, {0;3}"))
        #expect(editor.document.undoName == "Change Cull indices")
        editor.document.undo()
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullIndices] == .text(""))
    }
}
