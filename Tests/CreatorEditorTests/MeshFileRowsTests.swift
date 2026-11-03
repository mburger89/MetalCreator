import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorEditor

/// Import Mesh's file rows in the inspector (mesh import spec, the node): what the file is, and the buttons that fit.
@MainActor
struct MeshFileRowsTests {
    let registry = BuiltInNodes.registry

    func rows(_ reference: ImageReference?) -> [InspectorRow] {
        var node = registry.makeNode(ImportMeshNode.typeID)
        if let reference { node.inputValues[NodeSetting.meshFile] = .meshFile(reference) }
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        return editor.inspectorPage.sections.first { $0.title == "File" }?.rows ?? []
    }

    @Test func eachStateShowsItsRowsAndButtons() {
        #expect(rows(nil) == [
            .readOnly(label: "File", text: "No file chosen"),
            .button(title: "Choose File…", action: .chooseMeshFile),
        ])
        let hash = ImageHash(of: Data("a mesh".utf8))
        #expect(rows(.embedded(hash)) == [
            .readOnly(label: "File", text: "Embedded · \(hash.short)"),
            .button(title: "Choose File…", action: .chooseMeshFile),
        ])
        #expect(rows(.linked(relativePath: nil, absolutePath: "/tmp/part.stl")) == [
            .readOnly(label: "File", text: "Linked · part.stl"),
            .button(title: "Relink…", action: .relinkMeshFile), .button(title: "Embed", action: .embedMeshFile),
        ])
    }

    @Test func theUndoNamesAreFixedSentences() {
        #expect([UndoName.importMesh, UndoName.chooseMeshFile, UndoName.relinkMeshFile, UndoName.embedMeshFile]
            == ["Import Mesh", "Choose Mesh File", "Relink Mesh File", "Embed Mesh File"])
    }

    @Test func pressingAMeshFileButtonIsRecordedForTheAppShell() {
        let node = registry.makeNode(ImportMeshNode.typeID)
        let editor = makeEditor([node], registry: registry)
        for action in [InspectorAction.chooseMeshFile, .relinkMeshFile, .embedMeshFile] {
            editor.press(action, on: node.id)
            #expect(editor.inspectorRequest?.action == action)
        }
    }
}
