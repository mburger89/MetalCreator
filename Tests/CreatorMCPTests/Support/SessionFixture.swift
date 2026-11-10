import CreatorGraph
import CreatorKernel
import CreatorMCP
import CreatorNodes
import Foundation
import Synchronization
import Testing

final class Collected: Sendable {
    private let lines = Mutex<[Data]>([])
    func add(_ data: Data) { lines.withLock { $0.append(data) } }
    var all: [Data] { lines.withLock { $0 } }
}

/// A document over `FakeKernel` with Rectangle → Extrude → Output, and a server core over the catalogue.
@MainActor struct SessionFixture {
    let document: DocumentModel
    let session: DocumentModelSession
    let core: MCPServerCore
    let rectangle: NodeID
    let extrude: NodeID
    let output: NodeID

    init() async throws {
        document = DocumentModel(registry: BuiltInNodes.registry, kernel: FakeKernel())
        session = DocumentModelSession(document: document)
        core = MCPServerCore(
            session: session, tools: MCPCatalogue.tools, resources: MCPCatalogue.resources, serverVersion: "test"
        )
        let registry = BuiltInNodes.registry
        let rectangleNode = registry.makeNode("creator.rectangle")
        let extrudeNode = registry.makeNode("creator.extrude")
        let outputNode = registry.makeNode("creator.output")
        for node in [rectangleNode, extrudeNode, outputNode] { try document.perform(.addNode(node), name: "Add Node") }
        try document.perform(.connect(Link(from: Endpoint(node: rectangleNode.id, socket: "profile"),
                                           to: Endpoint(node: extrudeNode.id, socket: "profile"))), name: "Connect")
        try document.perform(.connect(Link(from: Endpoint(node: extrudeNode.id, socket: "solid"),
                                           to: Endpoint(node: outputNode.id, socket: "solid"))), name: "Connect")
        rectangle = rectangleNode.id
        extrude = extrudeNode.id
        output = outputNode.id
        await document.waitForEvaluation()
    }

    func call(_ tool: String, _ arguments: JSONValue = .object([:])) async throws -> (JSONValue, isError: Bool) {
        let request = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .int(1), "method": .string("tools/call"),
            "params": .object(["name": .string(tool), "arguments": arguments]),
        ])
        let sent = Collected()
        await core.handle(line: request.encoded()) { sent.add($0) }
        let reply = try JSONValue.parse(try #require(sent.all.last))
        let result = try #require(reply["result"])
        let text = try #require(result["content"]?.array?.first?["text"]?.string)
        let isError = result["isError"]?.bool ?? false
        return (isError ? .string(text) : try JSONValue.parse(Data(text.utf8)), isError)
    }
}
