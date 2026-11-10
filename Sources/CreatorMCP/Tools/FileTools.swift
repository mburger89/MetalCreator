import Foundation

/// New, open, save and export. The rules about unsaved changes and overwriting are the session's; this layer checks the arguments.
@MainActor public enum FileTools {
    static let exportKinds = ["step", "stl", "3mf"]

    private static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var fields: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { fields["required"] = .array(required.map { .string($0) }) }
        return .object(fields)
    }

    private static func flag(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    private static func pathProperty(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func result(_ outcome: SessionOutcome) -> MCPToolResult {
        switch outcome {
        case .refused(let sentence):
            return MCPToolResult.refused(sentence)
        case .done(let message):
            var fields: [String: JSONValue] = ["done": .bool(true)]
            if let message { fields["message"] = .string(message) }
            return .ok(.object(fields))
        }
    }

    /// The path argument as a file URL, or the refusal for a missing or relative one.
    private static func url(_ value: JSONValue?, required: Bool = true) -> Result<URL?, MCPRefusal> {
        guard let path = value?.string, !path.isEmpty else {
            return required ? .failure(MCPRefusal("Say which file, by its absolute path.")) : .success(nil)
        }
        guard AbsolutePath.isAbsolute(path) else { return .failure(MCPRefusal(AbsolutePath.refusal)) }
        return .success(URL(fileURLWithPath: path))
    }

    public static var tools: [MCPTool] {
        [
            MCPTool(
                name: "new_document",
                description: "Starts a new empty document. Refused while the open one has unsaved changes unless discard_unsaved is true.",
                inputSchema: schema(["discard_unsaved": flag("True to discard unsaved changes.")])
            ) { arguments, session, _ in
                result(session.newDocument(discardUnsaved: arguments["discard_unsaved"]?.bool ?? false))
            },
            MCPTool(
                name: "open_document",
                description: "Opens a .mcgraph file. Refused while the open document has unsaved changes unless discard_unsaved is true.",
                inputSchema: schema(
                    ["path": pathProperty("An absolute path."), "discard_unsaved": flag("True to discard unsaved changes.")],
                    required: ["path"]
                )
            ) { arguments, session, _ in
                switch url(arguments["path"]) {
                case .failure(let refusal): return .refused(refusal.sentence)
                case .success(let target):
                    guard let target else { return .refused(AbsolutePath.refusal) }
                    return result(session.open(target, discardUnsaved: arguments["discard_unsaved"]?.bool ?? false))
                }
            },
            MCPTool(
                name: "save_document",
                description: "Saves the document, to its own file or to the absolute path given. "
                    + "An existing file is only replaced when overwrite is true.",
                inputSchema: schema([
                    "path": pathProperty("An absolute path; omit to save to the document's own file."),
                    "overwrite": flag("True to replace an existing file."),
                ])
            ) { arguments, session, _ in
                switch url(arguments["path"], required: false) {
                case .failure(let refusal): return .refused(refusal.sentence)
                case .success(let target): return result(session.save(to: target, overwrite: arguments["overwrite"]?.bool ?? false))
                }
            },
            MCPTool(
                name: "export",
                description: "Exports the Output nodes' results as step, stl or 3mf. "
                    + "An existing file is only replaced when overwrite is true.",
                inputSchema: schema(
                    [
                        "kind": .object(["type": .string("string"), "enum": .array(exportKinds.map { .string($0) })]),
                        "path": pathProperty("An absolute path."),
                        "overwrite": flag("True to replace an existing file."),
                    ],
                    required: ["kind", "path"]
                )
            ) { arguments, session, context in
                guard let kind = arguments["kind"]?.string, exportKinds.contains(kind) else {
                    return .refused("Export kinds are step, stl and 3mf.")
                }
                switch url(arguments["path"]) {
                case .failure(let refusal): return .refused(refusal.sentence)
                case .success(let target):
                    guard let target else { return .refused(AbsolutePath.refusal) }
                    let outcome = await session.export(
                        kind, to: target, overwrite: arguments["overwrite"]?.bool ?? false, progress: context
                    )
                    return result(outcome)
                }
            },
        ]
    }
}

/// A refusal in words, for `Result`.
struct MCPRefusal: Error {
    let sentence: String
    init(_ sentence: String) { self.sentence = sentence }
}
