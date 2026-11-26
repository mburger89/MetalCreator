import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// A node that reads its `pcbFile` setting through the evaluation's resolver, as Import KiCad Board will.
enum BoardProbeNode: NodeDefinition {
    static let typeID = "test.boardProbe"
    static let displayName = "Board Probe"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("size", .integer)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .pcbFile(let reference)? = context.node.inputValues[NodeSetting.pcbFile] else { throw BoardImportProblem.notChosen }
        return NodeOutputs(["size": .integer(try context.images.pcbFileBytes(of: reference).count)])
    }
}

/// The Import KiCad Board node's file setting and file format 13.
@MainActor
struct BoardFileSettingTests {
    static let registry = NodeRegistry([BoardProbeNode.self])
    let folder = TempFolder()

    func probe(_ reference: ImageReference?) -> Node {
        var node = Self.registry.makeNode(BoardProbeNode.typeID)
        if let reference { node.inputValues[NodeSetting.pcbFile] = .pcbFile(reference) }
        return node
    }

    func document(_ nodes: [Node], url: URL? = nil) -> DocumentModel {
        let file = GraphFile(graph: Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })))
        return DocumentModel(file: file, registry: Self.registry, kernel: FakeKernel(), documentURL: url)
    }

    func reopened(_ data: Data) throws -> GraphFile { try GraphFileIO.decode(data, registry: Self.registry) }

    @Test func aBoardFileSettingRoundTripsAtFormat13() throws {
        #expect(GraphFile.currentFormatVersion == 19)
        let reference = ImageReference.linked(relativePath: "a/board.kicad_pcb", absolutePath: "/x/a/board.kicad_pcb")
        let node = probe(reference)
        let file = try reopened(try document([node]).fileData())
        #expect(file.formatVersion == 19)
        #expect(file.graph.nodes[node.id]?.inputValues[NodeSetting.pcbFile] == .pcbFile(reference))
        #expect(!NodeSetting.reservedForSockets.contains(NodeSetting.pcbFile))
        #expect(NodeSetting.all.contains(NodeSetting.pcbFile))
    }

    private static let formatTwelve = """
    {
      "definitions" : [],
      "formatVersion" : 12,
      "graph" : {
        "links" : [],
        "nodes" : [
          {
            "id" : "3F2504E0-4F89-41D3-9A0C-0305E82C3301", "inputValues" : {}, "isOutput" : false, "name" : "Board Probe",
            "position" : { "x" : 40, "y" : 20 }, "typeID" : "test.boardProbe", "typeVersion" : 1
          }
        ],
        "parameters" : []
      },
      "viewState" : { "canvasOffset" : { "x" : 0, "y" : 0 }, "canvasZoom" : 1, "dock" : "left", "showsLibrary" : true }
    }
    """

    @Test func aFormat12FileOpensUnchangedAndIsWrittenAs13() throws {
        let old = try reopened(Data(Self.formatTwelve.utf8))
        #expect(old.formatVersion == 12 && old.graph.nodes.count == 1)
        let today = try reopened(try document(Array(old.graph.nodes.values)).fileData())
        #expect(today.formatVersion == 19 && today.graph == old.graph)
    }

    @Test func savingElsewhereRewritesARelativePath() throws {
        let file = try folder.write(Data(count: 6), to: "doc/boards/b.kicad_pcb")
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        let node = probe(.linked(relativePath: "boards/b.kicad_pcb", absolutePath: absolute))
        let model = document([node], url: folder.url.appending(path: "doc/Plate.mcgraph"))
        let destination = folder.url.appending(path: "copy/Plate.mcgraph")
        let saved = try reopened(try model.fileData(savingTo: destination))
        #expect(saved.graph.nodes[node.id]?.inputValues[NodeSetting.pcbFile]
                == .pcbFile(.linked(relativePath: "../doc/boards/b.kicad_pcb", absolutePath: absolute)))
    }

    @Test func aBoardEditedOnDiskChangesTheCacheKeyAndRunsItsNode() async throws {
        let evaluator = Evaluator(registry: Self.registry, kernel: FakeKernel())
        let file = try folder.write(Data(count: 10), to: "b.kicad_pcb")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000_000))
        let node = probe(.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))
        #expect(ConstantValue.pcbFile(.embedded(ImageHash(of: Data()))).fileReference != nil)
        let graph = Graph(nodes: [node.id: node])
        let resolver = ImageResolver()
        _ = try await evaluator.evaluate(graph, demand: [node.id], images: resolver)
        #expect(try await evaluator.evaluate(graph, demand: [node.id], images: resolver).evaluatedNodes.isEmpty)
        try Data(count: 25).write(to: file)
        try folder.touch(file, Date(timeIntervalSince1970: 2_000_000))
        let changed = try await evaluator.evaluate(graph, demand: [node.id], images: resolver)
        #expect(changed.evaluatedNodes == [node.id])
        if case .one(.integer(let size))? = changed.results[node.id]?.outputs?["size"] {
            #expect(size == 25)
        } else {
            Issue.record("no size")
        }
    }

    @Test func problemsSaySoInWords() throws {
        let name = folder.url.lastPathComponent
        #expect(throws: BoardImportProblem.notAFile(name: name)) {
            try ImageResolver().pcbFileBytes(of: .linked(relativePath: nil, absolutePath: folder.url.path(percentEncoded: false)))
        }
        let gone = folder.url.appending(path: "gone.kicad_pcb")
        let missing = try #require(throws: BoardImportProblem.self) {
            try ImageResolver().pcbFileBytes(of: .linked(relativePath: nil, absolutePath: gone.path(percentEncoded: false)))
        }
        #expect(missing.message.hasPrefix("File 'gone.kicad_pcb' wasn't found at "))
        #expect(missing.message.hasSuffix(". Relink it in the inspector."))
        #expect(throws: BoardImportProblem.notChosen) { try ImageResolver().pcbFileBytes(of: .embedded(ImageHash(of: Data()))) }
        #expect(BoardImportProblem.notChosen.message == "Choose a KiCad board file.")
        #expect(BoardImportProblem.tooLarge.message == "This file is larger than the 256 MB limit.")
        #expect(BoardImportProblem.unreadable(name: "b", reason: "No.").message == "File 'b' couldn't be read: No.")
        #expect(BoardImportProblem.notAFile(name: "b").message == "File 'b' isn't a file.")
        #expect(Evaluator.message(for: BoardImportProblem.notChosen) == "Choose a KiCad board file.")
    }

    @Test func aFileOver256MegabytesIsRefusedWithoutReading() throws {
        let file = try folder.write(Data(), to: "huge.kicad_pcb")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ImageResolver.maxBoardFileBytes) + 1)
        try handle.close()
        #expect(throws: BoardImportProblem.tooLarge) {
            try ImageResolver().pcbFileBytes(of: .linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))
        }
    }

    @Test func aBoardHasItsBytes() throws {
        let file = try folder.write(Data("(kicad_pcb)".utf8), to: "ok.kicad_pcb")
        let bytes = try ImageResolver().pcbFileBytes(of: .linked(relativePath: nil, absolutePath: file.path(percentEncoded: false)))
        #expect(bytes == Data("(kicad_pcb)".utf8))
    }
}
