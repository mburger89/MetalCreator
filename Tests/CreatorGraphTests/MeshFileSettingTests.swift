import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// A node that reads its `meshFile` setting through the evaluation's resolver, as Import Mesh will (Task 3).
enum MeshProbeNode: NodeDefinition {
    static let typeID = "test.meshProbe"
    static let displayName = "Mesh Probe"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("size", .integer)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .meshFile(let reference)? = context.node.inputValues[NodeSetting.meshFile] else { throw MeshImportProblem.notChosen }
        return NodeOutputs(["size": .integer(try context.images.meshFileBytes(of: reference).count)])
    }
}

/// The Import Mesh node's file setting and file format 12 (mesh import spec, File setting): the Image Field's reference,
/// resolver and table, reused.
@MainActor
struct MeshFileSettingTests {
    static let registry = NodeRegistry([MeshProbeNode.self])
    let folder = TempFolder()
    let bytes = Data("solid mesh".utf8)

    func probe(_ reference: ImageReference?) -> Node {
        var node = Self.registry.makeNode(MeshProbeNode.typeID)
        if let reference { node.inputValues[NodeSetting.meshFile] = .meshFile(reference) }
        return node
    }

    func document(_ nodes: [Node], images: [ImageHash: Data] = [:], url: URL? = nil) -> DocumentModel {
        let file = GraphFile(graph: Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })), images: images)
        return DocumentModel(file: file, registry: Self.registry, kernel: FakeKernel(), documentURL: url)
    }

    func reopened(_ data: Data) throws -> GraphFile { try GraphFileIO.decode(data, registry: Self.registry) }

    @Test func aMeshFileSettingRoundTripsAtFormat12() throws {
        #expect(GraphFile.currentFormatVersion == 12)
        let hash = ImageHash(of: bytes)
        let linked = probe(.linked(relativePath: "a/part.stl", absolutePath: "/x/a/part.stl"))
        let embedded = probe(.embedded(hash))
        let data = try document([linked, embedded], images: [hash: bytes]).fileData()
        let file = try reopened(data)
        #expect(file.formatVersion == 12)
        let reference = ImageReference.linked(relativePath: "a/part.stl", absolutePath: "/x/a/part.stl")
        #expect(file.graph.nodes[linked.id]?.inputValues[NodeSetting.meshFile] == .meshFile(reference))
        #expect(file.graph.nodes[embedded.id]?.inputValues[NodeSetting.meshFile] == .meshFile(.embedded(hash)))
        #expect(file.images == [hash: bytes])
    }

    /// A file as format 11 wrote it: no `meshFile` anywhere, and a node that is not the probe's own.
    private static let formatEleven = """
    {
      "definitions" : [],
      "formatVersion" : 11,
      "graph" : {
        "links" : [],
        "nodes" : [
          {
            "id" : "3F2504E0-4F89-41D3-9A0C-0305E82C3301", "inputValues" : {}, "isOutput" : false, "name" : "Mesh Probe",
            "position" : { "x" : 40, "y" : 20 }, "typeID" : "test.meshProbe", "typeVersion" : 1
          },
          {
            "id" : "6BA7B810-9DAD-11D1-80B4-00C04FD430C8", "inputValues" : {}, "isOutput" : true, "name" : "Mesh Probe",
            "position" : { "x" : 240, "y" : 60 }, "typeID" : "test.meshProbe", "typeVersion" : 1
          }
        ],
        "parameters" : []
      },
      "viewState" : { "canvasOffset" : { "x" : 0, "y" : 0 }, "canvasZoom" : 1, "dock" : "left", "showsLibrary" : true }
    }
    """

    @Test func aFormat11FileOpensUnchangedAndIsWrittenAs12() throws {
        let old = try reopened(Data(Self.formatEleven.utf8))
        #expect(old.formatVersion == 11)
        #expect(old.graph.nodes.count == 2 && old.images.isEmpty)
        #expect(old.graph.nodes.values.allSatisfy { $0.inputValues[NodeSetting.meshFile] == nil })
        // The same graph, written and read today, is the same graph.
        let today = try reopened(try document(Array(old.graph.nodes.values)).fileData())
        #expect(today.formatVersion == 12)
        #expect(today.graph == old.graph)
        // And the earlier versions' numbers open too.
        var object = try #require(try JSONSerialization.jsonObject(with: Data(Self.formatEleven.utf8)) as? [String: Any])
        for version in 1...10 {
            object["formatVersion"] = version
            #expect(try reopened(try JSONSerialization.data(withJSONObject: object)).graph == old.graph)
        }
    }

    @Test func anEmbeddedMeshFileIsWrittenOnlyWhenUsedAndSurvivesAnEmbeddedSizeOverAPicturesLimit() throws {
        let hash = ImageHash(of: bytes)
        let unused = document([probe(nil)], images: [hash: bytes])
        #expect(try JSONSerialization.jsonObject(with: try unused.fileData()) is [String: Any])
        #expect(try reopened(try unused.fileData()).images.isEmpty)
        #expect(try reopened(try document([probe(.embedded(hash))], images: [hash: bytes]).fileData()).images.keys.contains(hash))
        let big = Data(count: ImageLimits.maxBytes + 1024)
        let bigHash = ImageHash(of: big)
        let kept = try reopened(try document([probe(.embedded(bigHash))], images: [bigHash: big]).fileData())
        #expect(kept.images[bigHash]?.count == big.count, "a mesh file may be larger than a picture")
    }

    @Test func aLinkedMeshFileEditedOnDiskRunsItsNodeOnce() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        let file = try folder.write(Data(count: 10), to: "part.stl")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000_000))
        let node = probe(.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))
        let hash = ImageHash(of: bytes)
        let other = probe(.embedded(hash))
        let held = ImageResolver(embedded: [hash: bytes])
        let graph = Graph(nodes: [node.id: node, other.id: other])
        _ = try await evaluator.evaluate(graph, demand: [node.id, other.id], images: held)
        #expect(try await evaluator.evaluate(graph, demand: [node.id, other.id], images: held).evaluatedNodes.isEmpty)
        try Data(count: 25).write(to: file)
        try folder.touch(file, Date(timeIntervalSince1970: 2_000_000))
        let changed = try await evaluator.evaluate(graph, demand: [node.id, other.id], images: held)
        #expect(changed.evaluatedNodes == [node.id], "only the node whose file changed runs")
        if case .one(.integer(let size))? = changed.results[node.id]?.outputs?["size"] {
            #expect(size == 25)
        } else {
            Issue.record("no size")
        }
    }

    @Test func savingElsewhereRewritesARelativePath() throws {
        let file = try folder.write(Data(count: 6), to: "doc/meshes/part.stl")
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        let node = probe(.linked(relativePath: "meshes/part.stl", absolutePath: absolute))
        let model = document([node], url: folder.url.appending(path: "doc/Plate.mcgraph"))
        let destination = folder.url.appending(path: "copy/Plate.mcgraph")
        let saved = try reopened(try model.fileData(savingTo: destination))
        #expect(saved.graph.nodes[node.id]?.inputValues[NodeSetting.meshFile]
                == .meshFile(.linked(relativePath: "../doc/meshes/part.stl", absolutePath: absolute)))
        model.didSave(to: destination)
        #expect(model.graph.nodes[node.id]?.inputValues[NodeSetting.meshFile]
                == .meshFile(.linked(relativePath: "../doc/meshes/part.stl", absolutePath: absolute)))
    }

    @Test func theClipboardCarriesAnEmbeddedMeshFile() {
        let hash = ImageHash(of: bytes)
        let other = ImageHash(of: Data("other".utf8))
        let embedded = probe(.embedded(hash))
        let linked = probe(.linked(relativePath: nil, absolutePath: "/x.stl"))
        let graph = Graph(nodes: [embedded.id: embedded, linked.id: linked])
        #expect(graph.embeddedImageHashes == [hash])
        #expect(!graph.embeddedImageHashes.contains(other))
        #expect(ConstantValue.meshFile(.embedded(hash)).fileReference == .embedded(hash))
        #expect(ConstantValue.image(.embedded(hash)).fileReference == .embedded(hash))
        #expect(ConstantValue.number(1).fileReference == nil)
    }

    @Test func aPathToAFolderOrDeviceIsRefused() throws {
        let name = folder.url.lastPathComponent
        #expect(throws: MeshImportProblem.notAFile(name: name)) { try ImageResolver.meshFileBytes(ofFileAt: folder.url) }
        #if !os(Windows)
        #expect(throws: MeshImportProblem.notAFile(name: "zero")) {
            try ImageResolver.meshFileBytes(ofFileAt: URL(filePath: "/dev/zero"))
        }
        #endif
    }

    @Test func aFileOverOneGigabyteIsRefusedWithoutReading() throws {
        let file = try folder.write(Data(), to: "huge.stl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(MeshImportLimits.maxFileBytes) + 1)
        try handle.close()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        try #require((attributes[.size] as? NSNumber)?.intValue == MeshImportLimits.maxFileBytes + 1, "sparse files aren't supported here")
        #expect(throws: MeshImportProblem.tooLarge) { try ImageResolver.meshFileBytes(ofFileAt: file) }
    }

    @Test func aMissingFileSaysSoWithoutTheWordImage() throws {
        let path = folder.url.appending(path: "meshes/part.stl")
        let problem = try #require(throws: MeshImportProblem.self) { try ImageResolver.meshFileBytes(ofFileAt: path) }
        #expect(problem.message.hasPrefix("File 'part.stl' wasn't found at "))
        #expect(problem.message.hasSuffix("/meshes/. Relink it in the inspector."))
        #expect(!problem.message.replacing(folder.url.path(percentEncoded: false), with: "").lowercased().contains("image"))
        #expect(throws: MeshImportProblem.embeddedMissing) { try ImageResolver().meshFileBytes(of: .embedded(ImageHash(of: bytes))) }
    }

    /// A mapped file truncated while it is parsed is a SIGBUS; a read file is whatever was read. The file is cut after the
    /// descriptor was opened and its size taken, with no timing involved.
    @Test func aFileTruncatedAfterItsSizeWasReadDoesNotCrash() throws {
        let file = try folder.write(Data(repeating: 0x61, count: 4_096), to: "cut.stl")
        let (handle, size) = try ImageResolver.openedRegularFile(file, name: "cut.stl", limit: MeshImportLimits.maxFileBytes)
        defer { try? handle.close() }
        let cutter = try FileHandle(forWritingTo: file)
        try cutter.truncate(atOffset: 100)
        try cutter.close()
        let data = try ImageResolver.meshFileBytes(from: handle, size: size, name: "cut.stl")
        #expect(size == 4_096 && data.count == 100)
    }

    @Test func aFileHasItsBytes() throws {
        let file = try folder.write(bytes, to: "part.stl")
        #expect(try ImageResolver.meshFileBytes(ofFileAt: file) == bytes)
    }
}
