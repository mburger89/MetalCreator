import Foundation

/// Reads and writes `.mcgraph` JSON.
public enum GraphFileIO {
    public static func encode(_ file: GraphFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Decodes and migrates old node versions. Unknown node types are kept as-is.
    public static func decode(_ data: Data, registry: NodeRegistry) throws -> GraphFile {
        var file = try JSONDecoder().decode(GraphFile.self, from: data)
        guard file.formatVersion <= GraphFile.currentFormatVersion else {
            throw GraphFileError.newerFormat(file.formatVersion)
        }
        for (id, node) in file.graph.nodes {
            guard let definition = registry[node.typeID], node.typeVersion < definition.typeVersion else { continue }
            var migrated = definition.migrate(node, from: node.typeVersion)
            migrated.typeVersion = definition.typeVersion
            file.graph.nodes[id] = migrated
        }
        return file
    }
}
