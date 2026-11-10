import Foundation

/// Answers one MCP request line at a time. The transport owns ordering: it must not call `handle` again until the
/// previous call has returned, so requests are handled strictly one after another.
@MainActor public final class MCPServerCore {
    private let session: any DocumentSession
    private let tools: [MCPTool]
    private let resources: [MCPResource]
    private let serverVersion: String

    public init(session: any DocumentSession, tools: [MCPTool], resources: [MCPResource], serverVersion: String) {
        self.session = session
        self.tools = tools
        self.resources = resources
        self.serverVersion = serverVersion
    }

    /// A line parsed off the main actor: the message, or the JSON-RPC error to send back for text that isn't JSON.
    public enum Parsed: Sendable {
        case message(JSONValue)
        case invalid(Data)
    }

    /// Parses one request line (up to 16 MiB of JSON). It touches no state, so the transport calls it on its own thread and hands
    /// only the result to the main actor.
    public nonisolated static func parse(line: Data) -> Parsed {
        do {
            return .message(try JSONValue.parse(line))
        } catch {
            return .invalid(JSONRPC.error(id: .null, code: JSONRPC.parseError, "The message isn't valid JSON."))
        }
    }

    /// Writes nothing for a notification, else one response line (plus progress notifications before it).
    public func handle(line: Data, send: @escaping @Sendable (Data) -> Void) async {
        switch Self.parse(line: line) {
        case .message(let message): await handle(message: message, send: send)
        case .invalid(let response): send(response)
        }
    }

    /// The same for a message the transport has already parsed.
    public func handle(message: JSONValue, send: @escaping @Sendable (Data) -> Void) async {
        guard message.object != nil, let method = message["method"]?.string else {
            send(JSONRPC.error(id: message["id"] ?? .null, code: JSONRPC.invalidRequest, "That isn't a JSON-RPC request."))
            return
        }
        guard let id = message["id"], id != .null else { return }
        let params = message["params"] ?? .object([:])
        switch method {
        case "initialize": send(JSONRPC.result(id: id, initialize(params)))
        case "ping": send(JSONRPC.result(id: id, .object([:])))
        case "tools/list": send(JSONRPC.result(id: id, toolList()))
        case "tools/call": send(await callTool(id: id, params: params, send: send))
        case "resources/list": send(JSONRPC.result(id: id, resourceList()))
        case "resources/read": send(readResource(id: id, params: params))
        default: send(JSONRPC.error(id: id, code: JSONRPC.methodNotFound, "There's no method “\(method)”."))
        }
    }

    private func initialize(_ params: JSONValue) -> JSONValue {
        let offered = params["protocolVersion"]?.string
        let version = offered.flatMap { MCPProtocol.supportedVersions.contains($0) ? $0 : nil } ?? MCPProtocol.supportedVersions[0]
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(true)]), "resources": .object(["listChanged": .bool(true)]),
            ]),
            "serverInfo": .object(["name": .string("MetalCreator"), "version": .string(serverVersion)]),
        ])
    }

    private func toolList() -> JSONValue {
        let entries = tools.map { tool in
            JSONValue.object([
                "name": .string(tool.name), "description": .string(tool.description), "inputSchema": tool.inputSchema,
            ])
        }
        return .object(["tools": .array(entries)])
    }

    private func callTool(id: JSONValue, params: JSONValue, send: @escaping @Sendable (Data) -> Void) async -> Data {
        guard let name = params["name"]?.string, let tool = tools.first(where: { $0.name == name }) else {
            return JSONRPC.error(id: id, code: JSONRPC.invalidParams, "There's no tool called “\(params["name"]?.string ?? "")”.")
        }
        var context = MCPCallContext()
        if let token = params["_meta"]?["progressToken"], token != .null {
            context = MCPCallContext { progress, total, message in
                var fields: [String: JSONValue] = ["progressToken": token, "progress": .number(progress)]
                if let total { fields["total"] = .number(total) }
                if let message { fields["message"] = .string(message) }
                send(JSONRPC.notification("notifications/progress", .object(fields)))
            }
        }
        let result = await tool.handler(params["arguments"] ?? .object([:]), session, context)
        return JSONRPC.result(id: id, .object([
            "content": .array([.object(["type": .string("text"), "text": .string(result.text)])]),
            "isError": .bool(result.isError),
        ]))
    }

    private func resourceList() -> JSONValue {
        let entries = resources.map { resource in
            JSONValue.object([
                "uri": .string(resource.uri), "name": .string(resource.name), "mimeType": .string(resource.mimeType),
            ])
        }
        return .object(["resources": .array(entries)])
    }

    private func readResource(id: JSONValue, params: JSONValue) -> Data {
        guard let uri = params["uri"]?.string, let resource = resources.first(where: { $0.uri == uri }) else {
            return JSONRPC.error(id: id, code: JSONRPC.invalidParams, "There's no resource “\(params["uri"]?.string ?? "")”.")
        }
        let content = JSONValue.object([
            "uri": .string(resource.uri), "mimeType": .string(resource.mimeType), "text": .string(resource.read(session)),
        ])
        return JSONRPC.result(id: id, .object(["contents": .array([content])]))
    }
}
