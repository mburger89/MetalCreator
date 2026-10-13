import Foundation
import Testing
@testable import CreatorGraph

/// The image types that reach the file (fields spec §5): the content hash, the reference and its stored setting.
struct ImageReferenceTests {
    static let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    static let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    @Test func aHashIsTheSHA256OfTheBytesInLowercaseHex() {
        #expect(ImageHash(of: Data("abc".utf8)).hex == Self.abc)
        #expect(ImageHash(of: Data()).hex == Self.empty)
        #expect(ImageHash(of: Data("abc".utf8)).short == "ba7816bf")
    }

    @Test func aHashReadsBackOnlyFromExactlySixtyFourLowercaseHexDigits() {
        #expect(ImageHash(hex: Self.abc) == ImageHash(of: Data("abc".utf8)))
        #expect(ImageHash(hex: Self.abc.uppercased()) == nil, "one spelling only, so equal hashes are equal keys")
        #expect(ImageHash(hex: String(Self.abc.dropLast())) == nil)
        #expect(ImageHash(hex: Self.abc + "0") == nil)
        #expect(ImageHash(hex: String(Self.abc.dropLast()) + "g") == nil)
        #expect(ImageHash(hex: "") == nil)
    }

    @Test func aDamagedHashInAFileFailsToDecode() throws {
        let good = try JSONDecoder().decode(ImageHash.self, from: Data("\"\(Self.abc)\"".utf8))
        #expect(good.hex == Self.abc)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ImageHash.self, from: Data("\"nope\"".utf8)) }
    }

    @Test func hashesSortByTheirDigits() {
        #expect([ImageHash(hex: Self.empty), ImageHash(hex: Self.abc)].compactMap { $0 }.sorted().map(\.hex) == [Self.abc, Self.empty])
    }

    @Test func referencesRoundTripAndTheJSONIsPinned() throws {
        let hash = try #require(ImageHash(hex: Self.abc))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let cases: [(ImageReference, String)] = [
            (.embedded(hash), #"{"hash":"\#(Self.abc)","kind":"embedded"}"#),
            (.linked(relativePath: "maps/vent.png", absolutePath: "/a/maps/vent.png"),
             #"{"absolutePath":"\/a\/maps\/vent.png","kind":"linked","relativePath":"maps\/vent.png"}"#),
            (.linked(relativePath: nil, absolutePath: "/a/vent.png"), #"{"absolutePath":"\/a\/vent.png","kind":"linked"}"#),
        ]
        for (reference, json) in cases {
            let data = try encoder.encode(reference)
            #expect(String(bytes: data, encoding: .utf8) == json)
            #expect(try JSONDecoder().decode(ImageReference.self, from: data) == reference)
        }
    }

    @Test func aReferenceWithAnUnknownKindOrNoPathFailsToDecode() {
        for json in [#"{"kind":"cloud"}"#, #"{"kind":"linked"}"#, #"{"kind":"embedded"}"#, #"{"kind":"embedded","hash":"x"}"#] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(ImageReference.self, from: Data(json.utf8)) }
        }
    }

    @Test func aLinkedFileIsNamedByItsLastPathComponentAndAnEmbeddedOneHasNoName() throws {
        let vent = ImageReference.linked(relativePath: "maps/vent-mask.png", absolutePath: "/x/maps/vent-mask.png")
        #expect(vent.fileName == "vent-mask.png")
        #expect(ImageReference.linked(relativePath: nil, absolutePath: "/x/y.jpg").fileName == "y.jpg")
        #expect(ImageReference.embedded(try #require(ImageHash(hex: Self.abc))).fileName == nil)
    }

    @Test func theImageSettingIsStoredAsAConstantNoSocketCanHold() throws {
        let reference = ImageReference.linked(relativePath: nil, absolutePath: "/a/b.png")
        let value = ConstantValue.image(reference)
        #expect(NodeSetting.image == "image" && NodeSetting.all.contains(NodeSetting.image))
        #expect(value.isFinite)
        #expect(Scalar(value) == nil, "a setting has no runtime value")
        #expect(try JSONDecoder().decode(ConstantValue.self, from: JSONEncoder().encode(value)) == value)
    }

    /// A file made before 7b-2 may have a group socket called "image"; the new setting must not take the name from it.
    @Test func aGroupSocketCalledImageIsStillAllowedAndSurvivesTheFile() throws {
        #expect(!GroupNaming.isReserved(NodeSetting.image) && !NodeSetting.reservedForSockets.contains(NodeSetting.image))
        #expect(GroupNaming.uniqueSocketName("image", among: []) == "image")
        let sockets = [SocketSpec("image", .number)]
        #expect(GroupNaming.problem(with: sockets) == nil)
        let definition = GroupDefinition(name: "Vent", inputs: sockets)
        let data = try GraphFileIO.encode(GraphFile(definitions: [definition.id: definition]))
        let reopened = try GraphFileIO.decode(data, registry: NodeRegistry([]))
        #expect(reopened.definitions[definition.id]?.inputs.map(\.name) == ["image"])
    }

    @Test func setInputStoresAnImageAndUndoPutsTheOldOneBack() throws {
        let node = Node(typeID: "creator.imageField", name: "Image Field")
        var graph = Graph(nodes: [node.id: node])
        let registry = NodeRegistry([])
        let first = ConstantValue.image(.linked(relativePath: nil, absolutePath: "/a.png"))
        let inverse = try graph.apply(.setInput(node.id, NodeSetting.image, first), registry: registry)
        #expect(graph.nodes[node.id]?.inputValues[NodeSetting.image] == first)
        _ = try graph.apply(inverse, registry: registry)
        #expect(graph.nodes[node.id]?.inputValues[NodeSetting.image] == nil)
    }
}
