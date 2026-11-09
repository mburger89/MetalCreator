import CreatorGraph
import CreatorKernel
import Foundation

/// Picture and mesh files for the nodes that hold one. Text settings go through `set_inputs`.
@MainActor public enum FileSettingTools {
    public static var tools: [MCPTool] {
        [
            MCPTool(
                name: "set_file",
                description: "Sets the file of an Image Field (a picture) or an Import Mesh node (STL or 3MF), linked or embedded.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "node": .object(["type": .string("string"), "description": .string("The node's ID or unique name.")]),
                        "path": .object(["type": .string("string"), "description": .string("An absolute path.")]),
                        "embed": .object(["type": .string("boolean"), "description": .string("True to keep a copy in the document.")]),
                    ]),
                    "required": .array([.string("node"), .string("path")]),
                ])
            ) { arguments, session, _ in
                if let refusal = session.editRefusal() { return .refused(refusal) }
                let node: NodeID
                switch Addressing.node(arguments["node"], in: session.content.graph) {
                case .failure(let refusal): return .refused(refusal.sentence)
                case .success(let id): node = id
                }
                guard let path = arguments["path"]?.string, !path.isEmpty else { return .refused("Say which file, by its absolute path.") }
                guard AbsolutePath.isAbsolute(path) else { return .refused(AbsolutePath.refusal) }
                let embed = arguments["embed"]?.bool ?? false
                return await EditOutcome.observe(session: session) {
                    await session.setFile(URL(fileURLWithPath: path), on: node, embed: embed)
                }
            },
        ]
    }
}

/// The one rule about paths a client sends: a POSIX root or a Windows drive letter.
enum AbsolutePath {
    static let refusal = "Paths must be absolute."

    static func isAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/") || (path.count > 2 && path.dropFirst().hasPrefix(":"))
    }
}
