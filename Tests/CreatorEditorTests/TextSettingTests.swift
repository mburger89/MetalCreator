import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct TextSettingTests {
    let registry = NodeRegistry([TextSettingTestNode.self])

    func editorWithNode() -> (EditorModel, Node) {
        let node = registry.makeNode(TextSettingTestNode.typeID)
        return (makeEditor([node], registry: registry), node)
    }

    @Test func aTextSettingShowsItsStoredText() {
        let (editor, node) = editorWithNode()
        editor.selection = [node.id]
        let expected = InputField(node: node.id, socket: NodeSetting.pathRule, label: "Path rule", type: nil, unit: .none,
                                  value: .text("{A} → {A}"))
        #expect(editor.inspectorPage.sections.map(\.title) == ["Rule"])
        #expect(editor.inspectorPage.sections[0].rows == [.text(expected)])
    }

    @Test func typingARuleStoresItAsOneNamedUndoStep() throws {
        let (editor, node) = editorWithNode()
        editor.selection = [node.id]
        guard case .text(let field)? = editor.inspectorPage.sections[0].rows.first else { Issue.record("no text row"); return }
        editor.setInput(field, to: .text("{A;B} → {B;A}"))
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.pathRule] == .text("{A;B} → {B;A}"))
        #expect(editor.document.undoName == "Change Path rule")
        editor.document.undo()
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.pathRule] == .text("{A} → {A}"))
    }

    @Test func aMissingSettingReadsAsEmptyText() {
        var node = registry.makeNode(TextSettingTestNode.typeID)
        node.inputValues[NodeSetting.pathRule] = nil
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        guard case .text(let field)? = editor.inspectorPage.sections[0].rows.first else { Issue.record("no text row"); return }
        #expect(field.value == nil)
        #expect(InspectorRowView.settingText(field) == "")
    }

    @Test func theControlNamesItsSetting() {
        #expect(InspectorControl.text(NodeSetting.pathRule).socket == NodeSetting.pathRule)
    }

    @Test func theTextRowDrawsItsLabelAndItsField() {
        let (editor, node) = editorWithNode()
        editor.selection = [node.id]
        #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
    }
}
