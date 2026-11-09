import Foundation
import Synchronization
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorMCP

@MainActor func stubSession() -> DocumentModelSession {
    DocumentModelSession(document: DocumentModel(registry: NodeRegistry([]), kernel: FakeKernel()))
}

final class Sent: Sendable {
    private let lines = Mutex<[Data]>([])
    func add(_ data: Data) { lines.withLock { $0.append(data) } }
    var all: [Data] { lines.withLock { $0 } }
}

@MainActor struct ProtocolCoreTests {
    func tools() -> [MCPTool] {
        [
            MCPTool(name: "echo", description: "Echoes.", inputSchema: .object(["type": .string("object")])) { args, _, _ in
                .ok(args)
            },
            MCPTool(name: "refuse", description: "Refuses.", inputSchema: .object(["type": .string("object")])) { _, _, _ in
                .refused("No.")
            },
        ]
    }

    func resources() -> [MCPResource] {
        [MCPResource(uri: "mc://doc", name: "Doc", mimeType: "text/plain") { _ in "hello" }]
    }

    func call(_ request: String) async throws -> [JSONValue] {
        let core = MCPServerCore(session: stubSession(), tools: tools(), resources: resources(), serverVersion: "1.2.3")
        let sent = Sent()
        await core.handle(line: Data(request.utf8)) { sent.add($0) }
        return try sent.all.map { line in
            #expect(line.last == 0x0A)
            return try JSONValue.parse(line)
        }
    }

    func callBytes(_ bytes: [UInt8]) async throws -> [JSONValue] {
        let core = MCPServerCore(session: stubSession(), tools: tools(), resources: resources(), serverVersion: "1.2.3")
        let sent = Sent()
        await core.handle(line: Data(bytes)) { sent.add($0) }
        return try sent.all.map { try JSONValue.parse($0) }
    }

    @Test func initializeNegotiatesTheVersion() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let result = try #require(out.first?["result"])
        #expect(result["protocolVersion"]?.string == "2025-06-18")
        #expect(result["serverInfo"]?["name"]?.string == "MetalCreator")
        #expect(result["serverInfo"]?["version"]?.string == "1.2.3")
        #expect(result["capabilities"]?["tools"] != nil)
        #expect(result["capabilities"]?["resources"] != nil)
    }

    @Test func initializeAcceptsTheOlderVersion() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        #expect(out.first?["result"]?["protocolVersion"]?.string == "2025-03-26")
    }

    @Test func initializeWithUnknownVersionAnswersOurNewest() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        #expect(out.first?["result"]?["protocolVersion"]?.string == "2025-06-18")
    }

    @Test func pingAnswersEmptyObject() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":"a","method":"ping"}"#)
        #expect(out.first?["result"] == .object([:]))
        #expect(out.first?["id"] == .string("a"))
    }

    @Test func notificationGetsNoResponse() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(out.isEmpty)
    }

    @Test func unknownMethodIs32601() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":2,"method":"nope/nope"}"#)
        #expect(out.first?["error"]?["code"]?.int == -32601)
    }

    @Test func garbageGetsParseError() async throws {
        for out in [try await call("{nope"), try await callBytes([0xFF, 0xFE])] {
            #expect(out.first?["error"]?["code"]?.int == -32700)
            #expect(out.first?["id"] == .null)
        }
    }

    @Test func nonObjectIsInvalidRequest() async throws {
        let out = try await call("[1,2]")
        #expect(out.first?["error"]?["code"]?.int == -32600)
    }

    @Test func toolsListNamesEveryTool() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try #require(out.first?["result"]?["tools"]?.array)
        #expect(tools.compactMap { $0["name"]?.string } == ["echo", "refuse"])
        #expect(tools.first?["description"]?.string == "Echoes.")
        #expect(tools.first?["inputSchema"]?["type"]?.string == "object")
    }

    @Test func toolCallReturnsContent() async throws {
        let out = try await call(
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{"a":1}}}"#)
        let result = try #require(out.first?["result"])
        #expect(result["isError"]?.bool == false)
        #expect(result["content"]?.array?.first?["type"]?.string == "text")
        #expect(result["content"]?.array?.first?["text"]?.string == #"{"a":1}"#)
    }

    @Test func unknownToolIsInvalidParams() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope"}}"#)
        #expect(out.first?["error"]?["code"]?.int == -32602)
    }

    @Test func toolErrorIsAResultNotAnRPCError() async throws {
        let out = try await call(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"refuse","arguments":{}}}"#)
        #expect(out.first?["error"] == nil)
        #expect(out.first?["result"]?["isError"]?.bool == true)
        #expect(out.first?["result"]?["content"]?.array?.first?["text"]?.string == "No.")
    }

    @Test func resourcesListAndRead() async throws {
        let list = try await call(#"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#)
        #expect(list.first?["result"]?["resources"]?.array?.first?["uri"]?.string == "mc://doc")
        let read = try await call(#"{"jsonrpc":"2.0","id":8,"method":"resources/read","params":{"uri":"mc://doc"}}"#)
        let item = read.first?["result"]?["contents"]?.array?.first
        #expect(item?["text"]?.string == "hello")
        #expect(item?["mimeType"]?.string == "text/plain")
        let missing = try await call(#"{"jsonrpc":"2.0","id":9,"method":"resources/read","params":{"uri":"mc://x"}}"#)
        #expect(missing.first?["error"]?["code"]?.int == -32602)
    }

    @Test func progressNotificationsPrecedeTheResponse() async throws {
        let progressTool = MCPTool(name: "slow", description: "", inputSchema: .object([:])) { _, _, context in
            context.progress?(1, 2, "half")
            return .ok(.null)
        }
        let core = MCPServerCore(session: stubSession(), tools: [progressTool], resources: [], serverVersion: "1")
        let sent = Sent()
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"slow","_meta":{"progressToken":"t"}}}"#
        await core.handle(line: Data(request.utf8)) { sent.add($0) }
        let lines = try sent.all.map { try JSONValue.parse($0) }
        #expect(lines.count == 2)
        #expect(lines.first?["method"]?.string == "notifications/progress")
        #expect(lines.first?["params"]?["progressToken"]?.string == "t")
        #expect(lines.last?["id"] == .int(1))
    }
}
