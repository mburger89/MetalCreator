import Foundation

/// Reads and writes `.mcgraph` JSON.
public enum GraphFileIO {
    private struct FormatHeader: Decodable {
        let formatVersion: Int
    }

    public static func encode(_ file: GraphFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Decodes and migrates old node versions, on the top level and inside every group definition.
    /// Unknown node types are kept as-is.
    public static func decode(_ data: Data, registry: NodeRegistry) throws -> GraphFile {
        let header = try JSONDecoder().decode(FormatHeader.self, from: data)
        guard header.formatVersion <= GraphFile.currentFormatVersion else {
            throw GraphFileError.newerFormat(header.formatVersion)
        }
        var file = try JSONDecoder().decode(GraphFile.self, from: data)
        file.graph = migrated(file.graph, registry: registry)
        for (id, definition) in file.definitions {
            file.definitions[id]?.graph = migrated(definition.graph, registry: registry)
        }
        return file
    }

    private static func migrated(_ graph: Graph, registry: NodeRegistry) -> Graph {
        var graph = graph
        for (id, node) in graph.nodes {
            guard let definition = registry[node.typeID], node.typeVersion < definition.typeVersion else { continue }
            var migrated = definition.migrate(node, from: node.typeVersion)
            migrated.typeVersion = definition.typeVersion
            graph.nodes[id] = migrated
        }
        return graph
    }
}
