import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// The document's pool of embedded images and the folder it is saved in, as `DocumentModel` hands them to every evaluation.
@MainActor
struct DocumentImageTests {
    let folder = TempFolder()

    func document(_ reference: ImageReference?, url: URL? = nil, images: [ImageHash: Data] = [:]) -> (DocumentModel, Node) {
        var node = EvaluatorImageTests.registry.makeNode(ImageProbeNode.typeID)
        node.isOutput = true  // a document evaluates what an output wants
        if let reference { node.inputValues[NodeSetting.image] = .image(reference) }
        let file = GraphFile(graph: Graph(nodes: [node.id: node]), images: images)
        return (DocumentModel(file: file, registry: EvaluatorImageTests.registry, kernel: FakeKernel(), documentURL: url), node)
    }

    func size(_ document: DocumentModel, _ node: Node) -> Int? {
        if case .one(.integer(let value))? = document.results[node.id]?.outputs?["size"] { value } else { nil }
    }

    @Test func addingImageBytesStoresThemOnceUnderTheirHashAndMakesAWaitingNodeRun() async throws {
        let data = Data("some picture".utf8)
        let (document, node) = document(.embedded(ImageHash(of: data)))
        await document.waitForEvaluation()
        if case .error? = document.results[node.id]?.state {} else { Issue.record("a node whose image is not held must fail") }
        let hash = document.addImage(data)
        #expect(hash == ImageHash(of: data) && document.addImage(data) == hash)
        #expect(document.images == [hash: data])
        await document.waitForEvaluation()
        #expect(size(document, node) == 12)
    }

    @Test func aFileOpenedWithImagesHoldsThemFromTheStart() async throws {
        let data = Data("held".utf8)
        let hash = ImageHash(of: data)
        let (document, node) = document(.embedded(hash), images: [hash: data])
        await document.waitForEvaluation()
        #expect(size(document, node) == 4 && document.images[hash] == data)
    }

    @Test func settingTheDocumentsURLRereadsRelativeLinks() async throws {
        try folder.write(Data(count: 6), to: "doc/vent.png")
        let (document, node) = document(.linked(relativePath: "vent.png", absolutePath: "/no/such/vent.png"))
        await document.waitForEvaluation()
        #expect(size(document, node) == nil, "unsaved: only the absolute path, which is wrong")
        document.documentURL = folder.url.appending(path: "doc/Plate.mcgraph")
        await document.waitForEvaluation()
        #expect(size(document, node) == 6)
    }
}
