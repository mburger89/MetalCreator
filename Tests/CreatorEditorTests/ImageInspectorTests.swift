import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorEditor

/// The Image Field in the inspector and on the clipboard (fields spec §5): what the picture is, the buttons that fit it, and
/// the pictures a copy carries.
@MainActor
struct ImageInspectorTests {
    let registry = BuiltInNodes.registry
    let picture = Data("a picture".utf8)

    func imageField(_ reference: ImageReference?) -> Node {
        var node = registry.makeNode(ImageFieldNode.typeID)
        if let reference { node.inputValues[NodeSetting.image] = .image(reference) }
        return node
    }

    func imageRows(_ node: Node) -> [InspectorRow] {
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        return editor.inspectorPage.sections.first { $0.title == "Image" }?.rows ?? []
    }

    @Test func noPictureOffersToChooseOrLinkOne() {
        #expect(imageRows(imageField(nil)) == [
            .readOnly(label: "Image", text: "No image chosen"),
            .button(title: "Choose Image…", action: .chooseImage), .button(title: "Link to File…", action: .linkImage),
        ])
    }

    @Test func anEmbeddedPictureIsNamedByItsHashAndOffersToChooseAnotherOrLinkIt() {
        let hash = ImageHash(of: picture)
        #expect(imageRows(imageField(.embedded(hash))) == [
            .readOnly(label: "Image", text: "Embedded · \(hash.short)"),
            .button(title: "Choose Image…", action: .chooseImage), .button(title: "Link Image…", action: .linkImage),
        ])
    }

    @Test func aLinkedPictureIsNamedByItsFileAndOffersToRelinkOrEmbedIt() {
        let reference = ImageReference.linked(relativePath: "maps/vent-mask.png", absolutePath: "/x/maps/vent-mask.png")
        #expect(imageRows(imageField(reference)) == [
            .readOnly(label: "Image", text: "Linked · vent-mask.png"),
            .button(title: "Relink…", action: .relinkImage), .button(title: "Embed Image", action: .embedImage),
        ])
    }

    @Test func theImageSectionComesFirstAndProjectionFollows() {
        let node = imageField(nil)
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        #expect(editor.inspectorPage.sections.map(\.title).prefix(2) == ["Image", "Projection"])
    }

    @Test func eachImageButtonIsHandedToTheAppShellAsARequest() {
        let node = imageField(nil)
        let editor = makeEditor([node], registry: registry)
        for action in [InspectorAction.chooseImage, .linkImage, .relinkImage, .embedImage] {
            let before = editor.inspectorRequest?.serial ?? 0
            editor.press(action, on: node.id)
            #expect(editor.inspectorRequest == InspectorRequest(node: node.id, action: action, serial: before + 1))
        }
    }

    @Test func undoNamesAreTheSpecs() {
        #expect([UndoName.chooseImage, UndoName.relinkImage, UndoName.embedImage, UndoName.linkImage]
            == ["Choose Image", "Relink Image", "Embed Image", "Link Image"])
    }

    // MARK: Clipboard

    @Test func copyingAnImageFieldCarriesItsPictureAndAPasteAnywhereFindsIt() throws {
        let hash = ImageHash(of: picture)
        let node = imageField(.embedded(hash))
        let source = makeEditor([node], registry: registry)
        source.document.addImage(picture)
        source.document.addImage(Data("an unused picture".utf8))
        source.selection = [node.id]
        source.copySelection()
        #expect(source.clipboard?.images == [hash: picture], "only what the copied nodes use")

        let other = makeEditor([], registry: registry)
        #expect(other.document.images.isEmpty)
        other.setClipboard(try #require(source.clipboard))
        other.paste()
        #expect(other.document.images == [hash: picture])
        let copy = try #require(other.selection.first)
        #expect(other.graph.nodes[copy]?.inputValues[NodeSetting.image] == .image(.embedded(hash)))
    }

    @Test func aLinkedPictureTravelsAsItsPathAlone() throws {
        let node = imageField(.linked(relativePath: nil, absolutePath: "/x/y.png"))
        let editor = makeEditor([node], registry: registry)
        editor.selection = [node.id]
        editor.copySelection()
        #expect(try #require(editor.clipboard).images.isEmpty)
    }

    @Test func aGroupsCopyCarriesThePicturesInsideItsDefinition() throws {
        let hash = ImageHash(of: picture)
        let inner = imageField(.embedded(hash))
        let definition = GroupDefinition(id: GroupID(), name: "Vents", inputs: [], outputs: [], graph: Graph(nodes: [inner.id: inner]))
        var group = registry.withGroups([definition.id: definition]).makeGroupNode(GroupNodes.groupTypeID, for: definition.id)
        group.position = .zero
        let document = DocumentModel(file: GraphFile(graph: Graph(nodes: [group.id: group]), definitions: [definition.id: definition]),
                                     registry: registry, kernel: FakeKernel())
        document.addImage(picture)
        let editor = EditorModel(document: document)
        editor.selection = [group.id]
        editor.copySelection()
        #expect(editor.clipboard?.images == [hash: picture])
    }
}
