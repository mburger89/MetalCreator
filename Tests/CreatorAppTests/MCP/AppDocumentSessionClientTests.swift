import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorMCP

/// How the app's session answers a client about time and alerts: the settle cap, and an export's warnings.
@MainActor
struct AppDocumentSessionClientTests {
    private func call(_ core: MCPServerCore, _ tool: String, _ arguments: JSONValue = .object([:])) async throws
        -> (result: JSONValue, isError: Bool) {
        let request = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .int(1), "method": .string("tools/call"),
            "params": .object(["name": .string(tool), "arguments": arguments]),
        ])
        let sent = Sent()
        await core.handle(line: request.encoded()) { sent.add($0) }
        let reply = try JSONValue.parse(try #require(sent.all.last))
        let result = try #require(reply["result"])
        let text = try #require(result["content"]?.array?.first?["text"]?.string)
        let isError = result["isError"]?.bool ?? false
        return (isError ? .string(text) : try JSONValue.parse(Data(text.utf8)), isError)
    }

    private func rig(_ graph: Graph) async -> (AppModel, MCPServerCore) {
        let app = await makeApp(graph)
        let core = MCPServerCore(session: AppDocumentSession(model: app), tools: MCPCatalogue.tools,
                                 resources: MCPCatalogue.resources, serverVersion: "test")
        return (app, core)
    }

    /// The whole settle, the model's own wait included, is capped by the limit.
    @Test func settleGivesUpAtTheLimitWhenAnEvaluationDoesNotFinish() async throws {
        let registry = NodeRegistry(BuiltInNodes.all + [StallNode.self])
        let app = AppModel(kernel: FakeKernel(), registry: registry)
        await app.settle()
        let session = AppDocumentSession(model: app)
        await StallNode.gate.close()
        var node = registry.makeNode(StallNode.typeID)
        node.isOutput = true
        try app.document.perform(.addNode(node), name: "Add Node")
        // No wall-clock bound: the whole suite shares the main actor, which can starve a timer for a long while. Before the fix
        // this never returned (the model's own wait ran uncapped until the gate opened, which only happens below).
        let settled = await session.settle(within: .milliseconds(200))
        #expect(!settled)
        await StallNode.gate.open()
        await app.settle()
        #expect(await session.settle(within: .seconds(60)))
    }

    /// A client's export reports its warnings in the tool result and raises no alert; the person's export still alerts.
    @Test func aClientExportReturnsItsWarningsWithoutAnAlert() async throws {
        var builder = GraphBuilder()
        let spheres = builder.add(ImplicitSphereNode.self, ["radius": .number(2)])
        let gradient = builder.add(LinearGradientNode.self, ["length": .number(10)])
        let union = builder.add(ImplicitUnionNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(spheres, "implicit", to: union, "shapes")
        builder.wire(gradient, "field", to: union, "blend radius")
        builder.wire(union, "implicit", to: output, "mesh")
        let (app, core) = await rig(builder.graph)
        let url = temporaryURL("mcp-warn.stl")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await call(core, "export", .object(["kind": .string("stl"), "path": .string(url.path)]))
        #expect(!result.isError)
        let message = try #require(result.result["message"]?.string)
        #expect(message.contains("with 1 warning"))
        #expect(message.contains("Union: “blend radius” is below 0 in places; it is held at 0 there."))
        #expect(app.alert == nil, "a client's export raises no modal alert")
        try await app.export(.stl, to: temporaryURL("person.stl"))
        #expect(app.alert != nil, "the person's export is unchanged")
    }
}
