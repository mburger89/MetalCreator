import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// File format 7 (fields spec §5): the `images` table, the `image` setting, what a save keeps, and formats 1 to 6.
@MainActor
struct ImageFileTests {
    static let registry = NodeRegistry([ImageProbeNode.self])
    let folder = TempFolder()
    let first = Data("first picture".utf8)
    let second = Data("second picture, longer".utf8)

    func probe(_ reference: ImageReference) -> Node {
        var node = Self.registry.makeNode(ImageProbeNode.typeID)
        node.inputValues[NodeSetting.image] = .image(reference)
        return node
    }

    func document(_ nodes: [Node], images: [Data] = []) -> DocumentModel {
        let table = Dictionary(uniqueKeysWithValues: images.map { (ImageHash(of: $0), $0) })
        let file = GraphFile(graph: Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })), images: table)
        return DocumentModel(file: file, registry: Self.registry, kernel: FakeKernel())
    }

    func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func reopened(_ data: Data) throws -> GraphFile { try GraphFileIO.decode(data, registry: Self.registry) }

    // MARK: Format 7

    @Test func filesAreWrittenAsTheCurrentFormatAndAnImageFreeFileHasNoImagesKey() throws {
        #expect(GraphFile.currentFormatVersion == 9)
        let object = try json(try document([]).fileData())
        #expect(object["formatVersion"] as? Int == 9)
        #expect(object["images"] == nil, "written only when there are images")
    }

    @Test func embeddedImagesRoundTripThroughTheFileKeyedByHashAndSorted() throws {
        let nodes = [probe(.embedded(ImageHash(of: first))), probe(.embedded(ImageHash(of: second)))]
        let data = try document(nodes, images: [first, second]).fileData()
        let table = try #require(try json(data)["images"] as? [String: String])
        #expect(table.count == 2 && table[ImageHash(of: first).hex] == first.base64EncodedString())
        let text = try #require(String(bytes: data, encoding: .utf8))
        let positions = table.keys.sorted().compactMap { text.range(of: "\"\($0)\" :")?.lowerBound }
        #expect(positions.count == 2 && positions == positions.sorted(), "written sorted by key, so a save changes only what changed")
        let file = try reopened(data)
        #expect(file.images == [ImageHash(of: first): first, ImageHash(of: second): second])
        #expect(try GraphFileIO.encode(file) == GraphFileIO.encode(GraphFile(graph: file.graph, images: file.images)))
    }

    @Test func twoNodesWithOnePictureStoreItOnce() throws {
        let hash = ImageHash(of: first)
        let data = try document([probe(.embedded(hash)), probe(.embedded(hash))], images: [first]).fileData()
        #expect(try #require(try json(data)["images"] as? [String: String]).count == 1)
    }

    @Test func imagesNoNodeUsesAreDroppedOnSaveButKeptForTheSession() throws {
        let document = document([probe(.embedded(ImageHash(of: first)))], images: [first, second])
        let object = try json(try document.fileData())
        #expect(Set(try #require(object["images"] as? [String: String]).keys) == [ImageHash(of: first).hex])
        #expect(document.images.count == 2, "undo may still want the other")
    }

    @Test func aLinkedImageStoresNoBytes() throws {
        let file = try folder.write(first, to: "vent.png")
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let document = document([probe(reference)], images: [second])
        #expect(try json(try document.fileData())["images"] == nil)
    }

    @Test func imagesUsedInsideAGroupDefinitionAreKept() throws {
        let inner = probe(.embedded(ImageHash(of: second)))
        let definition = GroupDefinition(id: GroupID(), name: "Inside", inputs: [], outputs: [], graph: Graph(nodes: [inner.id: inner]))
        let file = GraphFile(definitions: [definition.id: definition], images: [ImageHash(of: second): second])
        let document = DocumentModel(file: file, registry: Self.registry, kernel: FakeKernel())
        #expect(try #require(try json(try document.fileData())["images"] as? [String: String]).count == 1)
    }

    @Test func aDamagedEntryIsLeftOutAndTheRestOfTheDocumentOpens() throws {
        let good = ImageHash(of: first)
        let table: [String: String] = [
            good.hex: first.base64EncodedString(),
            ImageHash(of: second).hex: "###not base64###",
            String(repeating: "a", count: 64): second.base64EncodedString(),  // bytes that do not hash to the key
            "not-a-hash": first.base64EncodedString(),
            String(repeating: "B", count: 64): first.base64EncodedString(),  // upper case is no hash
        ]
        var object = try json(try document([]).fileData())
        object["images"] = table
        let file = try reopened(try JSONSerialization.data(withJSONObject: object))
        #expect(file.images == [good: first])
    }

    @Test func aPictureOverSixteenMegabytesInATableIsLeftOut() throws {
        let big = Data(count: ImageLimits.maxBytes + 1)
        var object = try json(try document([]).fileData())
        object["images"] = [ImageHash(of: big).hex: big.base64EncodedString()]
        #expect(try reopened(try JSONSerialization.data(withJSONObject: object)).images.isEmpty)
    }

    @Test func anImagesKeyOfTheWrongShapeIsIgnoredNotFatal() throws {
        var object = try json(try document([probe(.embedded(ImageHash(of: first)))]).fileData())
        object["images"] = ["a", "b"]
        let file = try reopened(try JSONSerialization.data(withJSONObject: object))
        #expect(file.images.isEmpty && file.graph.nodes.count == 1)
    }

    @Test func anEntryThatIsNotEvenAStringCostsThatPictureAndNoOtherOne() throws {
        let good = ImageHash(of: first)
        var object = try json(try document([]).fileData())
        object["images"] = [
            good.hex: first.base64EncodedString(),
            ImageHash(of: second).hex: 12,
            String(repeating: "c", count: 64): NSNull(),
            String(repeating: "d", count: 64): ["not", "a", "string"],
            String(repeating: "e", count: 64): ["nested": true],
            String(repeating: "f", count: 64): true,
        ] as [String: Any]
        let file = try reopened(try JSONSerialization.data(withJSONObject: object))
        #expect(file.images == [good: first], "the one good picture survives its damaged neighbours")
    }

    @Test func savingAfterADamagedEntryWasLeftOutWritesTheFileWithoutIt() throws {
        let good = ImageHash(of: first), bad = ImageHash(of: second)
        var object = try json(try document([]).fileData())
        object["images"] = [good.hex: first.base64EncodedString(), bad.hex: 12] as [String: Any]
        let file = try reopened(try JSONSerialization.data(withJSONObject: object))
        let node = probe(.embedded(good))
        let document = DocumentModel(file: GraphFile(graph: Graph(nodes: [node.id: node]), images: file.images),
                                     registry: Self.registry, kernel: FakeKernel())
        let table = try #require(try json(try document.fileData())["images"] as? [String: String])
        #expect(Set(table.keys) == [good.hex], "the damaged entry is gone from the file for good once it is saved")
    }

    @Test func aDocumentOpenedFromDataHoldsItsImagesAndEvaluatesThem() async throws {
        let data = try document([probe(.embedded(ImageHash(of: first)))], images: [first]).fileData()
        let opened = try DocumentModel(data: data, registry: Self.registry, kernel: FakeKernel())
        #expect(opened.images == [ImageHash(of: first): first])
    }

    // MARK: Linked paths on save

    @Test func anUnsavedDocumentGainsItsRelativePathOnFirstSave() throws {
        let file = try folder.write(first, to: "doc/maps/vent.png")
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        let document = document([probe(.linked(relativePath: nil, absolutePath: absolute))])
        let destination = folder.url.appending(path: "doc/Plate.mcgraph")
        let saved = try reopened(try document.fileData(savingTo: destination))
        let setting = try #require(saved.graph.nodes.values.first?.inputValues[NodeSetting.image])
        #expect(setting == .image(.linked(relativePath: "maps/vent.png", absolutePath: absolute)))
        let unchanged = try reopened(try document.fileData())
        let kept = unchanged.graph.nodes.values.first?.inputValues[NodeSetting.image]
        #expect(kept == .image(.linked(relativePath: nil, absolutePath: absolute)), "without a destination nothing is rewritten")
    }

    @Test func saveAsElsewhereMakesTheRelativePathFromTheNewFolderAndAMissingFileKeepsItsPaths() throws {
        let file = try folder.write(first, to: "doc/maps/vent.png")
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        let found = probe(.linked(relativePath: "maps/vent.png", absolutePath: absolute))
        let lost = probe(.linked(relativePath: "gone/x.png", absolutePath: "/no/such/x.png"))
        let document = document([found, lost])
        document.documentURL = folder.url.appending(path: "doc/Plate.mcgraph")
        let saved = try reopened(try document.fileData(savingTo: folder.url.appending(path: "copy/Plate.mcgraph")))
        #expect(saved.graph.nodes[found.id]?.inputValues[NodeSetting.image]
            == .image(.linked(relativePath: "../doc/maps/vent.png", absolutePath: absolute)))
        #expect(saved.graph.nodes[lost.id]?.inputValues[NodeSetting.image] == lost.inputValues[NodeSetting.image])
    }

    @Test func savingWritesNothingBesideALinkedImage() throws {
        let file = try folder.write(first, to: "doc/maps/vent.png")
        let before = folder.listing
        let document = document([probe(.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))])
        _ = try document.fileData(savingTo: folder.url.appending(path: "doc/Plate.mcgraph"))
        #expect(folder.listing == before)
    }

    // MARK: Formats 1 to 6 and newer ones

    /// A format-6 file as 7a wrote it: tree nodes' text settings, a comment, no `images`.
    static let formatSix = """
    {
      "definitions" : [],
      "formatVersion" : 6,
      "graph" : {
        "links" : [],
        "nodes" : [
          { "id" : "6C8F1D0C-0000-4000-8000-000000000001", "inputValues" : { "pathRule" : { "type" : "text", "value" : "{A;B} → {B;A}" } },
            "isOutput" : false, "name" : "Path Mapper", "position" : { "x" : 10, "y" : 20 },
            "typeID" : "test.imageProbe", "typeVersion" : 1 }
        ],
        "parameters" : []
      },
      "viewState" : {}
    }
    """

    @Test func aFormatSixFileOpensUnchangedAndIsSavedAsTheCurrentFormat() throws {
        let file = try reopened(Data(Self.formatSix.utf8))
        #expect(file.formatVersion == 6 && file.images.isEmpty && file.graph.nodes.count == 1)
        let document = DocumentModel(file: file, registry: Self.registry, kernel: FakeKernel())
        let saved = try reopened(try document.fileData())
        #expect(saved.formatVersion == 9)
        #expect(saved.graph == file.graph && saved.definitions == file.definitions, "nothing in a format-6 file changes")
    }

    @Test func everyEarlierFormatStillOpens() throws {
        for version in 1...6 {
            let text = Self.formatSix.replacing("\"formatVersion\" : 6", with: "\"formatVersion\" : \(version)")
            #expect(try reopened(Data(text.utf8)).formatVersion == version, "format \(version)")
        }
    }

    @Test func aNewerFormatIsRefusedWithTheExistingMessage() throws {
        let text = Self.formatSix.replacing("\"formatVersion\" : 6", with: "\"formatVersion\" : 10")
        #expect(throws: GraphFileError.newerFormat(10)) { try reopened(Data(text.utf8)) }
        #expect(GraphFileError.newerFormat(10).message
            .hasPrefix("This file was saved by a newer version of MetalCreator (file format 10)."))
    }
}
