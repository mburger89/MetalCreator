import CreatorGraph
import CreatorNodes
import Foundation
import Testing
@testable import CreatorEditor

/// A copy of a node with an embedded mesh file carries the file (mesh import spec, File setting), as an Image Field's picture.
@MainActor
struct MeshFileClipboardTests {
    @Test func copyingANodeWithAnEmbeddedMeshFileCarriesItAndAPasteFindsIt() throws {
        let registry = BuiltInNodes.registry
        let file = Data("solid part".utf8)
        let hash = ImageHash(of: file)
        var node = registry.makeNode(ImageFieldNode.typeID)  // any node: the setting is what is read
        node.inputValues[NodeSetting.meshFile] = .meshFile(.embedded(hash))
        let source = makeEditor([node], registry: registry)
        source.document.addImage(file)
        source.selection = [node.id]
        source.copySelection()
        #expect(source.clipboard?.images == [hash: file])
        let other = makeEditor([], registry: registry)
        other.setClipboard(try #require(source.clipboard))
        other.paste()
        #expect(other.document.images == [hash: file])
    }
}
