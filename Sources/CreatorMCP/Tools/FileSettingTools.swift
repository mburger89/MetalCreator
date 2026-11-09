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

/// The one rule about paths a client sends: a POSIX root, or on Windows a drive (`C:\`, `C:/`) or a UNC share (`\\server\share`).
enum AbsolutePath {
    static let refusal = "Paths must be absolute."

    static func isAbsolute(_ path: String) -> Bool {
        #if os(Windows)
        isWindowsAbsolute(path)
        #else
        path.hasPrefix("/")
        #endif
    }

    /// `X:\` or `X:/` (a letter, a colon, a separator), or `\\server\share` with both parts non-empty. `C:foo` is relative to a
    /// drive's current directory, so it is refused. Pure, so it is tested on every platform.
    static func isWindowsAbsolute(_ path: String) -> Bool {
        let characters = Array(path)
        if characters.count >= 3, characters[0].isASCII, characters[0].isLetter, characters[1] == ":",
           characters[2] == "\\" || characters[2] == "/" {
            return true
        }
        guard characters.count > 2, characters[0] == "\\", characters[1] == "\\" else { return false }
        let parts = path.dropFirst(2).split(separator: "\\", omittingEmptySubsequences: false)
        return parts.count >= 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }
}
