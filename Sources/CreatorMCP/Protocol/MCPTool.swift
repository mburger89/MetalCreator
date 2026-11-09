import Foundation

public enum MCPProtocol {
    /// Newest first: a client that offers none of these is answered with the first.
    public static let supportedVersions = ["2025-06-18", "2025-03-26"]
}

/// What a tool returns: text for the client and whether it is an error (an error here is a result, not a JSON-RPC error).
public struct MCPToolResult: Sendable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }

    public static func ok(_ value: JSONValue) -> Self { Self(text: value.text, isError: false) }
    public static func refused(_ sentence: String) -> Self { Self(text: sentence, isError: true) }
}

/// Lets a long call report progress; `progress` is nil unless the request carried `_meta.progressToken`.
public struct MCPCallContext: Sendable {
    public let progress: (@Sendable (Double, Double?, String?) -> Void)?

    public init(progress: (@Sendable (Double, Double?, String?) -> Void)? = nil) {
        self.progress = progress
    }
}

public struct MCPTool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let handler: @MainActor @Sendable (JSONValue, any DocumentSession, MCPCallContext) async -> MCPToolResult

    public init(
        name: String, description: String, inputSchema: JSONValue,
        handler: @escaping @MainActor @Sendable (JSONValue, any DocumentSession, MCPCallContext) async -> MCPToolResult
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }
}

public struct MCPResource: Sendable {
    public let uri: String
    public let name: String
    public let mimeType: String
    public let read: @MainActor @Sendable (any DocumentSession) -> String

    public init(
        uri: String, name: String, mimeType: String,
        read: @escaping @MainActor @Sendable (any DocumentSession) -> String
    ) {
        self.uri = uri
        self.name = name
        self.mimeType = mimeType
        self.read = read
    }
}
