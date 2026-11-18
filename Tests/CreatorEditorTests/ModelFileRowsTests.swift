import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorEditor

/// Import Model's file rows in the inspector (mesh import spec, the node): what the file is, and the buttons that fit.
@MainActor
struct ModelFileRowsTests {
    let registry = BuiltInNodes.registry

    func rows(_ reference: ImageReference?) -> [InspectorRow] {
        var node = registry.makeNode(ImportModelNode.typeID)
        if let reference { node.inputValues[NodeSetting.modelFile] = .modelFile(reference) }
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        return editor.inspectorPage.sections.first { $0.title == "File" }?.rows ?? []
    }

    @Test func eachStateShowsItsRowsAndButtons() {
        #expect(rows(nil) == [
            .readOnly(label: "File", text: "No file chosen"),
            .button(title: "Choose File…", action: .chooseModelFile),
        ])
        let hash = ImageHash(of: Data("a model".utf8))
        #expect(rows(.embedded(hash)) == [
            .readOnly(label: "File", text: "Embedded · \(hash.short)"),
            .button(title: "Choose File…", action: .chooseModelFile),
        ])
        #expect(rows(.linked(relativePath: nil, absolutePath: "/tmp/part.step")) == [
            .readOnly(label: "File", text: "Linked · part.step"),
            .button(title: "Relink…", action: .relinkModelFile), .button(title: "Embed", action: .embedModelFile),
        ])
    }

    @Test func theUndoNamesAreFixedSentences() {
        #expect([UndoName.importModel, UndoName.chooseModelFile, UndoName.relinkModelFile, UndoName.embedModelFile]
            == ["Import Model", "Choose Model File", "Relink Model File", "Embed Model File"])
    }

    @Test func pressingAModelFileButtonIsRecordedForTheAppShell() {
        let node = registry.makeNode(ImportModelNode.typeID)
        let editor = makeEditor([node], registry: registry)
        for action in [InspectorAction.chooseModelFile, .relinkModelFile, .embedModelFile] {
            editor.press(action, on: node.id)
            #expect(editor.inspectorRequest?.action == action)
        }
    }
}
